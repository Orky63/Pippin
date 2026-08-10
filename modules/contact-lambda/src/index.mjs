import { SESv2Client, SendEmailCommand } from "@aws-sdk/client-sesv2";

const ses = new SESv2Client({});
const FROM = process.env.FROM_EMAIL;
const TO = process.env.TO_EMAIL;

const json = (status, body) => ({
  statusCode: status,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  // Only POST allowed
  if (event.requestContext?.http?.method !== "POST") {
    return json(405, { error: "method not allowed" });
  }

  // Parse request body
  let payload;
  try {
    payload = JSON.parse(event.body || "{}");
  } catch {
    return json(400, { error: "invalid json" });
  }

  const { name, email, message, phone, _hp } = payload;

  // Honeypot: if _hp field is filled, silently return success (spam detection)
  if (_hp) {
    return json(200, { ok: true });
  }

  // Validate required fields
  if (!name || !email || !message) {
    return json(400, { error: "missing required fields: name, email, message" });
  }

  // Validate field lengths
  if (typeof name !== "string" || name.length > 200) {
    return json(400, { error: "name too long" });
  }

  if (typeof message !== "string" || message.length > 5000) {
    return json(400, { error: "message too long" });
  }

  try {
    // Send email via SES
    await ses.send(
      new SendEmailCommand({
        FromEmailAddress: FROM,
        Destination: { ToAddresses: [TO] },
        ReplyToAddresses: [email],
        Content: {
          Simple: {
            Subject: {
              Data: `Contact form: ${name}`,
              Charset: "UTF-8",
            },
            Body: {
              Text: {
                Data: `Name: ${name}\nEmail: ${email}\nPhone: ${phone || "(not provided)"}\n\n${message}`,
                Charset: "UTF-8",
              },
            },
          },
        },
      })
    );

    return json(200, { ok: true });
  } catch (error) {
    console.error("SES error:", error);
    return json(500, { error: "failed to send email" });
  }
};
