# Roteiro de Demonstração — FutStore

## Pré-requisitos (antes da apresentação)
1. PostgreSQL rodando (verificar: `pg_isready`)
2. Abrir **3 terminais** no computador
3. Ter o **Prisma Studio** aberto: `cd backend && npx prisma studio`
4. Ter o **psql** pronto: `"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d futstore`

---

## PARTE 1 — Mostrar a Estrutura (DDL) — ~5 min

### No psql, rodar:

```sql
-- Listar todas as 14 tabelas
\dt

-- Mostrar estrutura de uma tabela principal
\d "Product"

-- Mostrar estrutura de uma tabela com FK
\d "Review"

-- Mostrar todos os índices
\di
```

**Falar:** "Nosso banco tem 14 tabelas, com chaves primárias, estrangeiras, índices e constraints UNIQUE."

### Mostrar o ALTER TABLE (na migration):

```sql
-- Isso foi executado na migration: adicionou colunas novas ao Product
-- ALTER TABLE "Product" ADD COLUMN "brandId" TEXT, ADD COLUMN "categoryId" TEXT;
-- ALTER TABLE "Product" ADD CONSTRAINT "Product_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES "Brand"("id");
```

### Mostrar DROP (demonstrativo):

```sql
-- Exemplo de DROP (não executar de verdade!)
-- DROP INDEX IF EXISTS "Product_salesCount_idx";
-- DROP TABLE IF EXISTS "TabelaTemporaria";
```

---

## PARTE 2 — Mostrar os Dados (DML) — ~5 min

### No psql, mostrar volume:

```sql
-- Contar registros nas 5 tabelas principais
SELECT 'Product' AS tabela, count(*) AS registros FROM "Product"
UNION ALL SELECT 'User', count(*) FROM "User"
UNION ALL SELECT 'Order', count(*) FROM "Order"
UNION ALL SELECT 'OrderItem', count(*) FROM "OrderItem"
UNION ALL SELECT 'Review', count(*) FROM "Review";
```

### Demonstrar INSERT ao vivo:

```sql
INSERT INTO "Category" (id, name, slug, "createdAt")
VALUES ('demo_cat', 'Demo Apresentação', 'demo', NOW());

-- Verificar
SELECT * FROM "Category" WHERE id = 'demo_cat';
```

### Demonstrar UPDATE ao vivo:

```sql
UPDATE "Category" SET name = 'Demo Atualizado' WHERE id = 'demo_cat';

-- Verificar
SELECT * FROM "Category" WHERE id = 'demo_cat';
```

### Demonstrar DELETE ao vivo:

```sql
DELETE FROM "Category" WHERE id = 'demo_cat';

-- Verificar que sumiu
SELECT * FROM "Category" WHERE id = 'demo_cat';
```

**Falar:** "Demonstramos INSERT, UPDATE e DELETE ao vivo."

### No Prisma Studio (http://localhost:5555):
- Navegar pelas tabelas
- Mostrar os dados de Product (109 registros)
- Mostrar as relações (clicar num produto e ver os sizes, reviews)

---

## PARTE 3 — As 10 Queries com JOINs — ~8 min

### Executar cada query no psql:

```sql
-- QUERY 1: Top 10 produtos mais vendidos (3 tabelas: Product, Category, Brand)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q01_top_produtos_vendidos.sql'

-- QUERY 2: Receita por marca nos últimos 3 meses (4 tabelas)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q02_receita_por_marca.sql'

-- QUERY 3: Clientes VIP que gastaram mais de R$1000 (3 tabelas + HAVING)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q03_clientes_vip.sql'

-- QUERY 4: Produtos sem avaliação (3 tabelas + LEFT JOIN IS NULL)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q04_produtos_sem_avaliacao.sql'

-- QUERY 5: Cupons mais usados (3 tabelas + JOIN por texto)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q05_cupons_mais_usados.sql'

-- QUERY 6: Estoque baixo com último movimento (3 tabelas + subquery correlacionada)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q06_estoque_baixo.sql'

-- QUERY 7: Pedido completo detalhado (5 tabelas!)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q07_pedido_completo.sql'

-- QUERY 8: Wishlist não comprada (4 tabelas + NOT EXISTS)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q08_wishlist_nao_comprada.sql'

-- QUERY 9: Avaliação média por categoria (3 tabelas + Window Function RANK)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q09_avaliacao_media_categoria.sql'

-- QUERY 10: Usuários ativos vs inativos (3 tabelas + CTE + CASE)
\i 'C:/Users/antonio.melo/Documents/Projetos/FutStore/docs/queries/q10_usuarios_ativos_inativos.sql'
```

**Dica:** Para cada query, dizer rapidamente:
1. Qual a pergunta de negócio
2. Quantas tabelas envolve
3. Qual técnica SQL usa (GROUP BY, HAVING, LEFT JOIN, NOT EXISTS, Window Function, CTE...)

---

## PARTE 4 — Custo das Consultas — ~3 min

### Mostrar o EXPLAIN de 2-3 queries mais interessantes:

```sql
-- Query 1: mostra uso de Index Scan (eficiente)
EXPLAIN (ANALYZE, BUFFERS) 
SELECT p.name, p.team, c.name, b.name, p."salesCount", p.price
FROM "Product" p
INNER JOIN "Category" c ON c.id = p."categoryId"
INNER JOIN "Brand" b ON b.id = p."brandId"
WHERE p.active = true
ORDER BY p."salesCount" DESC LIMIT 10;

-- Query 6: mostra subquery correlacionada (custo alto estimado, baixo real)
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.name, ps.size, ps.stock, ps."minStock",
  (SELECT MAX(sm."createdAt") FROM "StockMovement" sm WHERE sm."productSizeId" = ps.id)
FROM "ProductSize" ps
INNER JOIN "Product" p ON p.id = ps."productId"
WHERE ps.stock < ps."minStock";
```

**Falar:** "O EXPLAIN mostra o plano de execução. Custo estimado vs real, Index Scan vs Seq Scan, uso de buffers."

---

## PARTE 5 — Linguagem Procedural (PL/pgSQL) — ~7 min

### 5.1 Mostrar a FUNCTION fn_ranking_vendas:

```sql
-- Chamar a function: retorna top 5 mais vendidos
SELECT * FROM fn_ranking_vendas(5);
```

### 5.2 Mostrar a FUNCTION fn_calcular_total:

```sql
-- Calcular total de um carrinho com cupom
SELECT fn_calcular_total(
  '[{"unitPrice": 349.90, "quantity": 2}, {"unitPrice": 499.90, "quantity": 1}]'::jsonb,
  'BEMVINDO10'
);
```

### 5.3 Demonstrar o TRIGGER trg_movimento_estoque ao vivo:

```sql
-- Ver estoque atual de um produto
SELECT ps.id, p.name, ps.size, ps.stock 
FROM "ProductSize" ps 
JOIN "Product" p ON p.id = ps."productId" 
LIMIT 3;

-- Anotar o ID do primeiro resultado (ex: 363)
-- Contar movimentações antes
SELECT count(*) FROM "StockMovement" WHERE "productSizeId" = 363;

-- Atualizar o estoque (trigger vai disparar!)
UPDATE "ProductSize" SET stock = stock - 1 WHERE id = 363;

-- Ver que criou uma nova movimentação automaticamente!
SELECT * FROM "StockMovement" WHERE "productSizeId" = 363 ORDER BY "createdAt" DESC LIMIT 3;
```

**Falar:** "O trigger registra automaticamente cada movimentação de estoque. Não precisamos fazer INSERT manual."

### 5.4 Demonstrar o TRIGGER trg_audit_status_pedido:

```sql
-- Pegar um pedido pendente
SELECT id, status FROM "Order" WHERE status = 'pendente' LIMIT 1;

-- Anotar o ID (ex: clxxxxxxxxx)
-- Mudar o status
UPDATE "Order" SET status = 'pago' WHERE id = 'COLAR_ID_AQUI';

-- Ver o log de auditoria que foi criado automaticamente!
SELECT * FROM "AuditLog" WHERE "tableName" = 'Order' ORDER BY "createdAt" DESC LIMIT 3;
```

### 5.5 Demonstrar a PROCEDURE sp_finalizar_pedido:

```sql
-- Criar um pedido completo via procedure!
CALL sp_finalizar_pedido(
  'user_001',
  '[{"productId": "COLAR_PRODUCT_ID", "size": "M", "unitPrice": 349.90, "quantity": 1}]'::jsonb,
  'BEMVINDO10',
  '{"fullName": "João Demo", "street": "Rua da Apresentação", "number": "100", "city": "São Paulo", "state": "SP", "zip": "01000000"}'::jsonb,
  '{"method": "pix"}'::jsonb
);

-- Ver que o pedido foi criado
SELECT * FROM "Order" ORDER BY "createdAt" DESC LIMIT 1;

-- Ver que o pagamento foi criado junto
SELECT * FROM "Payment" ORDER BY "paidAt" DESC LIMIT 1;
```

**Falar:** "A procedure faz tudo numa transação: valida estoque, cria pedido, itens, pagamento. Se der erro, faz ROLLBACK."

### 5.6 Mostrar tratamento de erro:

```sql
-- Tentar comprar com estoque insuficiente
CALL sp_finalizar_pedido(
  'user_001',
  '[{"productId": "COLAR_PRODUCT_ID", "size": "M", "unitPrice": 349.90, "quantity": 9999}]'::jsonb
);
-- Vai dar erro: "Estoque insuficiente" — demonstra RAISE EXCEPTION
```

---

## PARTE 6 — Encerramento — ~2 min

```sql
-- Resumo final: todas as tabelas e registros
SELECT 'Product' AS tabela, count(*) FROM "Product"
UNION ALL SELECT 'User', count(*) FROM "User"
UNION ALL SELECT 'Order', count(*) FROM "Order"
UNION ALL SELECT 'OrderItem', count(*) FROM "OrderItem"
UNION ALL SELECT 'Review', count(*) FROM "Review"
UNION ALL SELECT 'Address', count(*) FROM "Address"
UNION ALL SELECT 'Payment', count(*) FROM "Payment"
UNION ALL SELECT 'StockMovement', count(*) FROM "StockMovement"
UNION ALL SELECT 'AuditLog', count(*) FROM "AuditLog"
UNION ALL SELECT 'Wishlist', count(*) FROM "Wishlist"
ORDER BY 1;
```

**Falar:** "14 tabelas, 5 com mais de 100 registros, 10 queries com JOINs de 3-5 tabelas, procedures, functions, triggers, tudo rodando ao vivo."

---

## Checklist pré-apresentação
- [ ] PostgreSQL rodando
- [ ] `psql` abre e conecta no banco `futstore`
- [ ] Prisma Studio aberto em localhost:5555
- [ ] Pen drive com dump + código + documentação
- [ ] Este roteiro impresso ou aberto no celular
