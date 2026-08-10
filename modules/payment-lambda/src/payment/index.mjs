import Stripe from "stripe";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";

const sm = new SecretsManagerClient({});
let stripeClient = null;

async function getStripe() {
  if (stripeClient) return stripeClient;
  const { SecretString } = await sm.send(
    new GetSecretValueCommand({ SecretId: process.env.STRIPE_SECRETS_ARN })
  );
  const { secret_key } = JSON.parse(SecretString);
  stripeClient = new Stripe(secret_key);
  return stripeClient;
}

const json = (status, body) => ({
  statusCode: status,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  if (event.requestContext?.http?.method !== "POST") {
    return json(405, { error: "method not allowed" });
  }

  let payload;
  try {
    payload = JSON.parse(event.body || "{}");
  } catch {
    return json(400, { error: "invalid json" });
  }

  const { amount, currency = "usd", metadata = {} } = payload;

  // Validate amount (in cents, minimum $0.50)
  if (!Number.isInteger(amount) || amount < 50) {
    return json(400, { error: "amount must be integer cents >= 50" });
  }

  try {
    const stripe = await getStripe();
    const intent = await stripe.paymentIntents.create({
      amount,
      currency,
      automatic_payment_methods: { enabled: true },
      metadata,
    });

    return json(200, {
      client_secret: intent.client_secret,
      payment_intent_id: intent.id,
    });
  } catch (error) {
    console.error("Stripe error:", error);
    return json(500, { error: "failed to create payment intent" });
  }
};
