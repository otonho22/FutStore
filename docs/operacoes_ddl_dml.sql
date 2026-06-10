-- ============================================================
-- FutStore — Demonstração de Operações DDL e DML
-- ============================================================
-- Este arquivo demonstra todas as operações exigidas:
-- DDL: CREATE TABLE, ALTER TABLE, DROP TABLE
-- DML: INSERT, UPDATE, DELETE
-- ============================================================


-- ============================================================
-- DDL — CREATE TABLE
-- ============================================================
-- Exemplo: Criação da tabela Product (extraído da migration init)

CREATE TABLE "Product" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "team" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "price" DOUBLE PRECISION NOT NULL,
    "imageUrl" TEXT NOT NULL,
    "images" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "category" TEXT NOT NULL,
    "categoryId" TEXT,
    "brandId" TEXT,
    "salesCount" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Product_pkey" PRIMARY KEY ("id")
);

-- Exemplo: Criação da tabela Review (migration add_new_tables)

CREATE TABLE "Review" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "rating" INTEGER NOT NULL,
    "comment" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Review_pkey" PRIMARY KEY ("id")
);


-- ============================================================
-- DDL — ALTER TABLE
-- ============================================================
-- Exemplo 1: Adicionando colunas categoryId e brandId em Product
-- (extraído da migration add_new_tables)

ALTER TABLE "Product"
    ADD COLUMN "brandId" TEXT,
    ADD COLUMN "categoryId" TEXT;

-- Exemplo 2: Adicionando Foreign Keys

ALTER TABLE "Product"
    ADD CONSTRAINT "Product_categoryId_fkey"
    FOREIGN KEY ("categoryId") REFERENCES "Category"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Product"
    ADD CONSTRAINT "Product_brandId_fkey"
    FOREIGN KEY ("brandId") REFERENCES "Brand"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;

-- Exemplo 3: Criando índice para melhorar performance

CREATE INDEX "Product_brandId_idx" ON "Product"("brandId");


-- ============================================================
-- DDL — DROP (demonstrativo — não executar em produção)
-- ============================================================
-- Exemplo: Remoção de índice que não é mais necessário

DROP INDEX IF EXISTS "Product_salesCount_idx";

-- Exemplo: Remoção de tabela temporária (demonstrativo)

DROP TABLE IF EXISTS "_temp_migration_backup";


-- ============================================================
-- DML — INSERT
-- ============================================================
-- Exemplo 1: Inserindo uma categoria

INSERT INTO "Category" (id, name, slug, "createdAt")
VALUES ('cat_demo_01', 'Copa do Mundo', 'copa-do-mundo', NOW());

-- Exemplo 2: Inserindo um produto completo

INSERT INTO "Product" (id, name, team, description, price, "imageUrl", category, "categoryId", "salesCount", active, "createdAt")
VALUES (
    'prod_demo_01',
    'Brasil Copa 2026 Home',
    'Seleção Brasileira',
    'Camisa oficial da Seleção Brasileira para a Copa do Mundo 2026.',
    449.90,
    '/jerseys/selecao-brasileira.jpg',
    'Copa do Mundo',
    'cat_demo_01',
    0,
    true,
    NOW()
);

-- Exemplo 3: Inserindo um usuário

INSERT INTO "User" (id, email, "displayName", role, "acceptedTerms", "createdAt")
VALUES ('user_demo_01', 'joao@email.com', 'João Silva', 'customer', true, NOW());


-- ============================================================
-- DML — UPDATE
-- ============================================================
-- Exemplo 1: Atualizando o status de um pedido (usado no painel admin)

UPDATE "Order"
SET status = 'enviado',
    "trackingCode" = 'BR1234567890123',
    "statusHistory" = "statusHistory"::jsonb || jsonb_build_array(
        jsonb_build_object('status', 'enviado', 'at', NOW()::TEXT)
    )
WHERE id = (SELECT id FROM "Order" LIMIT 1);

-- Exemplo 2: Atualizando preço de um produto

UPDATE "Product"
SET price = 399.90
WHERE id = 'prod_demo_01';

-- Exemplo 3: Desativando um cupom expirado

UPDATE "Coupon"
SET active = false
WHERE "validUntil" < NOW();


-- ============================================================
-- DML — DELETE
-- ============================================================
-- Exemplo 1: Removendo item da wishlist

DELETE FROM "Wishlist"
WHERE "userId" = 'user_demo_01'
  AND "productId" = 'prod_demo_01';

-- Exemplo 2: Removendo dados de demonstração

DELETE FROM "Product" WHERE id = 'prod_demo_01';
DELETE FROM "Category" WHERE id = 'cat_demo_01';
DELETE FROM "User" WHERE id = 'user_demo_01';
