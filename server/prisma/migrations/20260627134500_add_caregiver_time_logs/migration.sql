-- CreateTable
CREATE TABLE `CaregiverTimeLog` (
    `id` VARCHAR(191) NOT NULL,
    `caregiverId` VARCHAR(191) NOT NULL,
    `timeIn` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `timeOut` DATETIME(3) NULL,
    `totalMinutes` INTEGER NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `CaregiverTimeLog_caregiverId_timeIn_idx`(`caregiverId`, `timeIn`),
    INDEX `CaregiverTimeLog_timeOut_idx`(`timeOut`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `CaregiverTimeLog` ADD CONSTRAINT `CaregiverTimeLog_caregiverId_fkey` FOREIGN KEY (`caregiverId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
