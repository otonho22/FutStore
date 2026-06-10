-- ============================================================
-- QUERY 03: Clientes VIP (Gastaram Mais de R$ 1.000)
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Quais clientes gastaram mais de R$ 1.000 na loja?
--   Lista com total gasto, quantidade de pedidos e cidade.
--
-- TABELAS ENVOLVIDAS (3):
--   User, Order, Address
--
-- TÉCNICA: JOIN + GROUP BY + HAVING + agregação
--
-- EXPLICAÇÃO:
--   Unimos User com Order para calcular o total gasto por cliente,
--   e com Address para mostrar a cidade principal (endereço padrão).
--   A cláusula HAVING filtra apenas clientes cujo total de compras
--   ultrapassa R$ 1.000. Isso identifica os clientes mais valiosos
--   para ações de marketing e fidelização.
-- ============================================================

SELECT
    u."displayName"                     AS cliente,
    u.email                             AS email,
    a.city                              AS cidade,
    a.state                             AS estado,
    COUNT(o.id)                         AS qtd_pedidos,
    ROUND(SUM(o.total)::NUMERIC, 2)    AS total_gasto
FROM "User" u
INNER JOIN "Order" o   ON o."userId" = u.id
LEFT JOIN "Address" a  ON a."userId" = u.id AND a."isDefault" = true
WHERE o.status != 'cancelado'
GROUP BY u.id, u."displayName", u.email, a.city, a.state
HAVING SUM(o.total) > 1000
ORDER BY total_gasto DESC;
