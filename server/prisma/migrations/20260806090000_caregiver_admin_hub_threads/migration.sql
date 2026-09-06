-- Caregiver and Family users must never share a conversation. Conversations
-- are now keyed by the non-admin peer, with Admin users as the only hub members.

-- Remove inaccessible legacy pooled conversations that had no peer.
DELETE FROM `Conversation`
WHERE `peerId` IS NULL;

-- Keep one caregiver/admin conversation per caregiver and move any messages
-- from older per-resident caregiver threads into that canonical conversation.
CREATE TEMPORARY TABLE `CaregiverConversationKeep` AS
SELECT `peerId`, MIN(`id`) AS `keepId`
FROM `Conversation`
WHERE `type` = 'CAREGIVER'
GROUP BY `peerId`;

INSERT IGNORE INTO `ConversationMember` (`id`, `conversationId`, `userId`, `lastReadAt`)
SELECT CONCAT('cm_', REPLACE(UUID(), '-', '')), keepers.`keepId`, members.`userId`, MAX(members.`lastReadAt`)
FROM `ConversationMember` members
INNER JOIN `Conversation` conversations
  ON conversations.`id` = members.`conversationId`
INNER JOIN `CaregiverConversationKeep` keepers
  ON keepers.`peerId` = conversations.`peerId`
WHERE conversations.`type` = 'CAREGIVER'
  AND conversations.`id` <> keepers.`keepId`
GROUP BY keepers.`keepId`, members.`userId`;

UPDATE `Message` messages
INNER JOIN `Conversation` conversations
  ON conversations.`id` = messages.`conversationId`
INNER JOIN `CaregiverConversationKeep` keepers
  ON keepers.`peerId` = conversations.`peerId`
SET messages.`conversationId` = keepers.`keepId`
WHERE conversations.`type` = 'CAREGIVER'
  AND conversations.`id` <> keepers.`keepId`;

DELETE members
FROM `ConversationMember` members
INNER JOIN `Conversation` conversations
  ON conversations.`id` = members.`conversationId`
INNER JOIN `CaregiverConversationKeep` keepers
  ON keepers.`peerId` = conversations.`peerId`
WHERE conversations.`type` = 'CAREGIVER'
  AND conversations.`id` <> keepers.`keepId`;

DELETE conversations
FROM `Conversation` conversations
INNER JOIN `CaregiverConversationKeep` keepers
  ON keepers.`peerId` = conversations.`peerId`
WHERE conversations.`type` = 'CAREGIVER'
  AND conversations.`id` <> keepers.`keepId`;

DROP TEMPORARY TABLE `CaregiverConversationKeep`;

-- Caregiver/admin threads are not resident-specific anymore.
UPDATE `Conversation`
SET `residentId` = NULL
WHERE `type` = 'CAREGIVER';

ALTER TABLE `Conversation` DROP FOREIGN KEY `Conversation_residentId_fkey`;
ALTER TABLE `Conversation` DROP FOREIGN KEY `Conversation_peerId_fkey`;
DROP INDEX `Conversation_residentId_peerId_key` ON `Conversation`;

ALTER TABLE `Conversation`
  MODIFY `residentId` VARCHAR(191) NULL,
  MODIFY `peerId` VARCHAR(191) NOT NULL;

CREATE UNIQUE INDEX `Conversation_peerId_type_key` ON `Conversation`(`peerId`, `type`);

ALTER TABLE `Conversation` ADD CONSTRAINT `Conversation_residentId_fkey`
  FOREIGN KEY (`residentId`) REFERENCES `Resident`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `Conversation` ADD CONSTRAINT `Conversation_peerId_fkey`
  FOREIGN KEY (`peerId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
