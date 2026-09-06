-- CreateTable
CREATE TABLE `CaregiverActivityLog` (
    `id` VARCHAR(191) NOT NULL,
    `caregiverId` VARCHAR(191) NOT NULL,
    `residentId` VARCHAR(191) NOT NULL,
    `activityType` ENUM('CARE_TASK', 'MEDICATION') NOT NULL,
    `itemTitle` VARCHAR(191) NOT NULL,
    `itemDetails` VARCHAR(191) NULL,
    `completedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `medicationEventId` VARCHAR(191) NULL,
    `careTaskEventId` VARCHAR(191) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `CaregiverActivityLog_caregiverId_completedAt_idx`(`caregiverId`, `completedAt`),
    INDEX `CaregiverActivityLog_residentId_completedAt_idx`(`residentId`, `completedAt`),
    INDEX `CaregiverActivityLog_activityType_completedAt_idx`(`activityType`, `completedAt`),
    INDEX `CaregiverActivityLog_medicationEventId_idx`(`medicationEventId`),
    INDEX `CaregiverActivityLog_careTaskEventId_idx`(`careTaskEventId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `CaregiverActivityLog` ADD CONSTRAINT `CaregiverActivityLog_caregiverId_fkey` FOREIGN KEY (`caregiverId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `CaregiverActivityLog` ADD CONSTRAINT `CaregiverActivityLog_residentId_fkey` FOREIGN KEY (`residentId`) REFERENCES `Resident`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill current completed medication events.
INSERT INTO `CaregiverActivityLog` (
    `id`,
    `caregiverId`,
    `residentId`,
    `activityType`,
    `itemTitle`,
    `itemDetails`,
    `completedAt`,
    `medicationEventId`,
    `createdAt`
)
SELECT
    CONCAT('cal_med_', me.`id`),
    me.`updatedById`,
    me.`residentId`,
    'MEDICATION',
    m.`name`,
    NULLIF(CONCAT_WS(' - ', NULLIF(m.`dosage`, ''), NULLIF(m.`type`, '')), ''),
    me.`updatedAt`,
    me.`id`,
    CURRENT_TIMESTAMP(3)
FROM `MedicationEvent` me
INNER JOIN `Medication` m ON m.`id` = me.`medicationId`
WHERE me.`status` = 'TAKEN'
  AND me.`updatedById` IS NOT NULL;

-- Backfill current completed care task events.
INSERT INTO `CaregiverActivityLog` (
    `id`,
    `caregiverId`,
    `residentId`,
    `activityType`,
    `itemTitle`,
    `itemDetails`,
    `completedAt`,
    `careTaskEventId`,
    `createdAt`
)
SELECT
    CONCAT('cal_task_', cte.`id`),
    cte.`updatedById`,
    cte.`residentId`,
    'CARE_TASK',
    ct.`title`,
    NULLIF(CONCAT_WS(' - ', NULLIF(ct.`type`, ''), NULLIF(ct.`scheduledTime`, '')), ''),
    COALESCE(cte.`timeCompleted`, cte.`updatedAt`),
    cte.`id`,
    CURRENT_TIMESTAMP(3)
FROM `CareTaskEvent` cte
INNER JOIN `CareTask` ct ON ct.`id` = cte.`careTaskId`
WHERE cte.`status` = 'DONE'
  AND cte.`updatedById` IS NOT NULL;
