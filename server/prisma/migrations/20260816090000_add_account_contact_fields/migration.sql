ALTER TABLE `FamilyProfile`
  ADD COLUMN `secondaryContactNumber` VARCHAR(191) NULL;

ALTER TABLE `CaregiverProfile`
  ADD COLUMN `contactNumber` VARCHAR(191) NULL,
  ADD COLUMN `address` VARCHAR(191) NULL;
