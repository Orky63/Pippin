import Stripe from "stripe";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";

const sm = new SecretsManagerClient({});
const ddb = new DynamoDBClient({});
let webhookSecret = null;

async function getWebhookSecret() {
  if (webhookSecret) return webhookSecret;
  const { SecretString } = await sm.send(
    new GetSecretValueCommand({ SecretId: process.env.STRIPE_SECRETS_ARN })
  );
  const { webhook_secret } = JSON.parse(SecretString);
  webhookSecret = webhook_secret;
  return webhookSecret;
}

const json = (status, body) => ({
  statusCode: status,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  const sig = event.headers?.["stripe-signature"];
  const rawBody = event.isBase64Encoded
    ? Buffer.from(event.body, "base64").toString("utf8")
    : event.body;

  if (!sig || !rawBody) {
    return json(400, { error: "missing stripe-signature header or body" });
  }

  // Verify Stripe webhook signature
  let stripeEvent;
  try {
    const secret = await getWebhookSecret();
    const stripe = new Stripe("");  // Empty key is fine for webhook verification
    stripeEvent = stripe.webhooks.constructEvent(rawBody, sig, secret);
  } catch (err) {
    console.error("Webhook signature verification failed:", err.message);
    return json(400, { error: `webhook signature verification failed: ${err.message}` });
  }

  // Idempotency check: only process each event once
  const ttl = Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60;  // 7-day TTL
  try {
    await ddb.send(
      new PutItemCommand({
        TableName: process.env.IDEMPOTENCY_TABLE,
        Item: {
          event_id: { S: stripeEvent.id },
          event_type: { S: stripeEvent.type },
          expires_at: { N: String(ttl) },
        },
        ConditionExpression: "attribute_not_exists(event_id)",
      })
    );
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") {
      // Duplicate event - already processed
      console.log(`Duplicate event ${stripeEvent.id}, returning success`);
      return json(200, { ok: true, duplicate: true });
    }
    throw err;
  }

  // Log event for debugging (extend with business logic per client)
  console.log(JSON.stringify({
    event_id: stripeEvent.id,
    event_type: stripeEvent.type,
    data: stripeEvent.data,
  }));

  return json(200, { ok: true });
};
