CREATE TABLE `FacilityInfo` (
    `id` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL DEFAULT 'Lifehouse Nursing Home',
    `contactNumber` VARCHAR(191) NULL,
    `email` VARCHAR(191) NULL,
    `address` VARCHAR(191) NULL,
    `updatedById` VARCHAR(191) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO `FacilityInfo` (`id`, `name`, `createdAt`, `updatedAt`)
VALUES ('details', 'Lifehouse Nursing Home', CURRENT_TIMESTAMP(3), CURRENT_TIMESTAMP(3));
