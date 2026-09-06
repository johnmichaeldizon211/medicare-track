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

describe("auth routes", () => {
  it("rejects public family registration", async () => {
    const unique = Date.now();
    const response = await request(app)
      .post("/api/v1/auth/register/family")
      .send({
        email: `family${unique}@example.com`,
        password: "password123",
        username: `family${unique}`,
        contactName: "Test Family",
        relationship: "Daughter",
        contactNumber: "09171234567",
        address: "Test Address",
        resident: {
          name: "Resident Test",
          room: "201",
          age: 70,
          gender: "Female",
          address: "Facility"
        }
      });

    expect(response.status).toBe(403);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("ADMIN_ONLY_ACCOUNT_CREATION");
  });
});

describeWithDb("auth routes with seeded database", () => {
  it("lets admin create a family account", async () => {
    const adminToken = await login("admin@lifehouse.com", "password123");
    const unique = Date.now();

    const response = await request(app)
      .post("/api/v1/admin/users/patient")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({
        email: `adminfamily${unique}@example.com`,
        password: "password123",
        username: `adminfamily${unique}`,
        contactName: "Admin Family",
        relationship: "Son",
        contactNumber: "09171234567",
        address: "Family Address",
        resident: {
          name: "Admin Resident",
          room: "301",
          age: 71,
          birthday: "1/1/1955",
          gender: "Male",
          address: "Facility"
        }
      });

    expect(response.status).toBe(201);
    expect(response.body.success).toBe(true);
    expect(response.body.data.role).toBe("FAMILY");
    expect(response.body.data.familyProfile.resident.name).toBe("Admin Resident");
  });

  it("logs in seeded admin", async () => {
    const response = await request(app)
      .post("/api/v1/auth/login")
      .send({ email: "admin@lifehouse.com", password: "password123" });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(response.body.data.user.role).toBe("ADMIN");
  });
});
