import { PrismaClient } from "@prisma/client";
import { hashPassword } from "../src/lib/password.js";

const prisma = new PrismaClient();

async function main() {
  await prisma.messageRead.deleteMany();
  await prisma.message.deleteMany();
  await prisma.conversationMember.deleteMany();
  await prisma.conversation.deleteMany();
  await prisma.careTaskEvent.deleteMany();
  await prisma.careTask.deleteMany();
  await prisma.medicationEvent.deleteMany();
  await prisma.medicationReminder.deleteMany();
  await prisma.medication.deleteMany();
  await prisma.residentAssignment.deleteMany();
  await prisma.residentCondition.deleteMany();
  await prisma.passwordResetOtp.deleteMany();
  await prisma.refreshToken.deleteMany();
  await prisma.notification.deleteMany();
  await prisma.devicePushToken.deleteMany();
  await prisma.notificationSetting.deleteMany();
  await prisma.facilityInfo.deleteMany();
  await prisma.familyProfile.deleteMany();
  await prisma.caregiverProfile.deleteMany();
  await prisma.resident.deleteMany();
  await prisma.user.deleteMany();

  const passwordHash = await hashPassword("password123");

  await prisma.facilityInfo.create({
    data: {
      id: "details",
      name: "Lifehouse Nursing Home",
      contactNumber: "09171234567",
      email: "admin@lifehouse.com",
      address: "Lifehouse Care Facility"
    }
  });

  const admin = await prisma.user.create({
    data: {
      email: "admin@lifehouse.com",
      username: "admin",
      passwordHash,
      role: "ADMIN",
      notificationSetting: {
        create: {
          pushEnabled: true,
          soundEnabled: true,
          vibrationEnabled: true,
          medicationCareTaskRemindersEnabled: true,
          urgentAlertsEnabled: true,
          adminMessagesEnabled: true
        }
      }
    }
  });

  const caregiver = await prisma.user.create({
    data: {
      email: "sarah.reyes@lifehouse.com",
      username: "sarah.reyes",
      passwordHash,
      role: "CAREGIVER",
      caregiverProfile: {
        create: {
          displayName: "Sarah Reyes"
        }
      },
      notificationSetting: {
        create: {
          pushEnabled: true,
          soundEnabled: true,
          vibrationEnabled: true,
          medicationCareTaskRemindersEnabled: true,
          urgentAlertsEnabled: true,
          adminMessagesEnabled: true
        }
      }
    }
  });

  const resident = await prisma.resident.create({
    data: {
      name: "Ryzamae Santos",
      room: "201",
      age: 72,
      birthday: "1954-02-14",
      gender: "Female",
      address: "Lifehouse Care Facility",
      medicalNotes: "Monitor blood pressure and hydration.",
      overallStatus: "STABLE",
      conditions: {
        createMany: {
          data: [
            { name: "Hypertension" },
            { name: "Type 2 Diabetes" }
          ]
        }
      }
    }
  });

  const family = await prisma.user.create({
    data: {
      email: "ryzamae@gmail.com",
      username: "ryzamae.family",
      passwordHash,
      role: "FAMILY",
      familyProfile: {
        create: {
          residentId: resident.id,
          contactName: "Ryzamae Santos",
          relationship: "Daughter",
          contactNumber: "09171234567",
          address: "Quezon City"
        }
      },
      notificationSetting: {
        create: {
          pushEnabled: true,
          soundEnabled: true,
          vibrationEnabled: true,
          medicationCareTaskRemindersEnabled: true,
          urgentAlertsEnabled: true,
          adminMessagesEnabled: true
        }
      }
    }
  });

  await prisma.residentAssignment.create({
    data: {
      residentId: resident.id,
      caregiverId: caregiver.id,
      state: "ASSIGNED"
    }
  });

  const familyConversation = await prisma.conversation.create({
    data: {
      residentId: resident.id,
      peerId: family.id,
      type: "FAMILY",
      members: {
        createMany: {
          data: [
            { userId: admin.id },
            { userId: family.id }
          ]
        }
      }
    }
  });

  await prisma.message.create({
    data: {
      conversationId: familyConversation.id,
      senderId: admin.id,
      content: "Welcome to the family care thread for Ryzamae Santos.",
      reads: {
        create: {
          userId: admin.id
        }
      }
    }
  });

  const caregiverConversation = await prisma.conversation.create({
    data: {
      residentId: null,
      peerId: caregiver.id,
      type: "CAREGIVER",
      members: {
        createMany: {
          data: [
            { userId: admin.id },
            { userId: caregiver.id }
          ]
        }
      }
    }
  });

  await prisma.message.create({
    data: {
      conversationId: caregiverConversation.id,
      senderId: admin.id,
      content: "Welcome to the caregiver care thread for Ryzamae Santos.",
      reads: {
        create: {
          userId: admin.id
        }
      }
    }
  });

  console.log("Seed completed", {
    admin: admin.email,
    caregiver: caregiver.email,
    family: family.email,
    resident: resident.name,
    demoPassword: "password123"
  });
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
