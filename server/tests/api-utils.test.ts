import { describe, expect, it } from "vitest";
import { ok } from "../src/utils/api.js";

describe("API response helpers", () => {
  it("removes password hashes from nested success payloads", () => {
    const response = ok({
      id: "user-1",
      passwordHash: "$2a$10$secret",
      familyProfile: {
        user: {
          id: "user-2",
          passwordHash: "$2a$10$nested"
        }
      }
    });

    expect(response).toEqual({
      success: true,
      data: {
        id: "user-1",
        familyProfile: {
          user: {
            id: "user-2"
          }
        }
      }
    });
  });
});
