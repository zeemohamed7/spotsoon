// Supabase Edge Function: dispatch minimal SpotSoon lifecycle notifications to APNs.
// Deploy with JWT verification disabled only because this function validates the
// independent PUSH_DISPATCH_SECRET before using server credentials.

type PushEvent = {
  id: string
  signal_id: string
  recipient_user_id: string
  event_type: string
  title: string
  body: string
  attempt_count: number
}

type PushDevice = { id: string; token: string; environment: "sandbox" | "production" }

const required = (name: string): string => {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`Missing server secret: ${name}`)
  return value
}

const base64url = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "")

const utf8 = (value: string) => new TextEncoder().encode(value)

const importAPNsKey = async (pem: string): Promise<CryptoKey> => {
  const body = pem.replace(/-----[^-]+-----/g, "").replaceAll(/\s/g, "")
  const bytes = Uint8Array.from(atob(body), (character) => character.charCodeAt(0))
  return crypto.subtle.importKey("pkcs8", bytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"])
}

let cachedJWT: { value: string; createdAt: number } | undefined
const apnsJWT = async (): Promise<string> => {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJWT && now - cachedJWT.createdAt < 50 * 60) return cachedJWT.value
  const header = base64url(utf8(JSON.stringify({ alg: "ES256", kid: required("APNS_KEY_ID") })))
  const claims = base64url(utf8(JSON.stringify({ iss: required("APNS_TEAM_ID"), iat: now })))
  const unsigned = `${header}.${claims}`
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, await importAPNsKey(required("APNS_PRIVATE_KEY")), utf8(unsigned),
  ))
  const value = `${unsigned}.${base64url(signature)}`
  cachedJWT = { value, createdAt: now }
  return value
}

const rest = async (path: string, init: RequestInit = {}): Promise<Response> => {
  const serviceKey = required("SUPABASE_SERVICE_ROLE_KEY")
  return fetch(`${required("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      ...init.headers,
    },
  })
}

const updateEvent = async (id: string, values: Record<string, unknown>) => {
  const response = await rest(`push_notification_events?id=eq.${id}`, {
    method: "PATCH",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify(values),
  })
  if (!response.ok) throw new Error(`Could not update notification event (${response.status})`)
}

const deactivateDevice = async (id: string) => {
  await rest(`push_device_tokens?id=eq.${id}`, {
    method: "PATCH",
    body: JSON.stringify({ is_active: false, invalidated_at: new Date().toISOString() }),
  })
}

const deliver = async (event: PushEvent, device: PushDevice): Promise<"sent" | "invalid"> => {
  const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"
  const response = await fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJWT()}`,
      "apns-topic": required("APNS_BUNDLE_ID"),
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": "0",
      "apns-id": event.id,
    },
    body: JSON.stringify({
      aps: { alert: { title: event.title, body: event.body }, sound: "default" },
      notification_event_id: event.id,
      signal_id: event.signal_id,
      lifecycle_event: event.event_type,
    }),
  })
  if (response.ok) return "sent"
  const result = await response.json().catch(() => ({})) as { reason?: string }
  if (response.status === 410 || ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(result.reason ?? "")) {
    await deactivateDevice(device.id)
    return "invalid"
  }
  throw new Error(`APNs ${response.status}: ${result.reason ?? "delivery_failed"}`)
}

Deno.serve(async (request) => {
  try {
    const expected = required("PUSH_DISPATCH_SECRET")
    if (request.headers.get("x-push-dispatch-secret") !== expected) {
      return new Response("Unauthorized", { status: 401 })
    }

    const claimed = await rest("rpc/claim_push_notification_events", {
      method: "POST",
      body: JSON.stringify({ p_limit: 25 }),
    })
    if (!claimed.ok) throw new Error(`Could not claim notification events (${claimed.status})`)
    const events = await claimed.json() as PushEvent[]

    for (const event of events) {
      try {
        const devicesResponse = await rest(
          `push_device_tokens?select=id,token,environment&user_id=eq.${event.recipient_user_id}&is_active=eq.true`,
        )
        if (!devicesResponse.ok) throw new Error(`Could not load recipient devices (${devicesResponse.status})`)
        const devices = await devicesResponse.json() as PushDevice[]
        for (const device of devices) await deliver(event, device)
        await updateEvent(event.id, {
          delivery_status: "sent", sent_at: new Date().toISOString(),
          processing_started_at: null, last_error: null,
        })
      } catch (error) {
        const delaySeconds = Math.min(3600, 30 * 2 ** Math.min(event.attempt_count, 7))
        await updateEvent(event.id, {
          delivery_status: "failed",
          processing_started_at: null,
          next_attempt_at: new Date(Date.now() + delaySeconds * 1000).toISOString(),
          last_error: String(error).slice(0, 500),
        })
      }
    }
    return Response.json({ processed: events.length })
  } catch (error) {
    return Response.json({ error: String(error) }, { status: 500 })
  }
})
