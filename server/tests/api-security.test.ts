import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "../src/app.js";
import { isDatabaseAvailable } from "./helpers/db.js";

const app = createApp();
const hasDb = await isDatabaseAvailable();
const describeWithDb = hasDb ? describe : describe.skip;

async function login(email: string, password: string) {
  const response = await request(app)
    .post("/api/v1/auth/login")
    .send({ email, password });

  expect(response.status).toBe(200);
  expect(response.body.success).toBe(true);
  return response.body.data.tokens.accessToken as string;
}

describe("api security", () => {
  it("rejects unauthenticated residents access", async () => {
    const response = await request(app).get("/api/v1/residents");

    expect(response.status).toBe(401);
    expect(response.body.success).toBe(false);
  });
});

describeWithDb("api security with seeded database", () => {
  it("prevents caregiver from admin endpoint", async () => {
    const caregiverToken = await login("sarah.reyes@lifehouse.com", "password123");

    const response = await request(app)
      .post("/api/v1/admin/users/caregiver")
      .set("Authorization", `Bearer ${caregiverToken}`)
      .send({
        name: "No Access",
        email: `blocked${Date.now()}@example.com`,
        username: `blocked${Date.now()}`,
        password: "password123"
      });

    expect(response.status).toBe(403);
    expect(response.body.success).toBe(false);
  });
});
