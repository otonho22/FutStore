-- AlterTable
ALTER TABLE "Coupon" ADD COLUMN     "firstPurchaseOnly" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "maxUsesGlobal" INTEGER,
ADD COLUMN     "maxUsesPerCustomer" INTEGER;

-- AlterTable
ALTER TABLE "ProductSize" ADD COLUMN     "minStock" INTEGER NOT NULL DEFAULT 3;
