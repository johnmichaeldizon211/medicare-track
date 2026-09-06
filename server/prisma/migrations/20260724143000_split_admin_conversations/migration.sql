-- AlterTable
ALTER TABLE `Conversation` ADD COLUMN `type` ENUM('FAMILY', 'CAREGIVER') NOT NULL DEFAULT 'FAMILY',
    ADD COLUMN `peerId` VARCHAR(191) NULL;

-- Remove memberships from legacy pooled conversations so mixed Family/Caregiver
-- threads cannot be accessed after the split. New per-peer threads are created
-- lazily by the API sync helper.
DELETE FROM `ConversationMember`
WHERE `conversationId` IN (
    SELECT `id` FROM `Conversation` WHERE `peerId` IS NULL
);

-- DropIndex
DROP INDEX `Conversation_residentId_key` ON `Conversation`;

-- CreateIndex
CREATE INDEX `Conversation_peerId_idx` ON `Conversation`(`peerId`);

-- CreateIndex
CREATE INDEX `Conversation_residentId_type_idx` ON `Conversation`(`residentId`, `type`);

-- CreateIndex
CREATE UNIQUE INDEX `Conversation_residentId_peerId_key` ON `Conversation`(`residentId`, `peerId`);

-- AddForeignKey
ALTER TABLE `Conversation` ADD CONSTRAINT `Conversation_peerId_fkey` FOREIGN KEY (`peerId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
