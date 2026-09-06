-- AlterTable
ALTER TABLE `NotificationSetting`
    ADD COLUMN `medicationCareTaskRemindersEnabled` BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN `urgentAlertsEnabled` BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN `adminMessagesEnabled` BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE `Notification` (
    `id` VARCHAR(191) NOT NULL,
    `userId` VARCHAR(191) NOT NULL,
    `category` ENUM('MEDICATION_CARE_TASK', 'URGENT_ALERT', 'ADMIN_MESSAGE') NOT NULL,
    `title` VARCHAR(191) NOT NULL,
    `body` TEXT NOT NULL,
    `data` JSON NULL,
    `sourceKey` VARCHAR(191) NULL,
    `readAt` DATETIME(3) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    UNIQUE INDEX `Notification_sourceKey_key`(`sourceKey`),
    INDEX `Notification_userId_readAt_createdAt_idx`(`userId`, `readAt`, `createdAt`),
    INDEX `Notification_category_createdAt_idx`(`category`, `createdAt`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `Notification` ADD CONSTRAINT `Notification_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
