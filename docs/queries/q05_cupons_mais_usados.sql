-- ============================================================
-- QUERY 05: Ranking de Cupons Mais Utilizados
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Quais cupons de desconto são mais utilizados pelos clientes?
--   Qual o total de desconto concedido por cada cupom?
--
-- TABELAS ENVOLVIDAS (3):
--   Coupon, Order, User
--
-- TÉCNICA: JOIN via campo texto (couponCode) + GROUP BY + SUM
--
-- EXPLICAÇÃO:
--   A tabela Order armazena o código do cupom como texto (snapshot),
--   não como FK. Fazemos JOIN entre Order e Coupon pelo campo code.
--   Também unimos com User para contar quantos clientes distintos
--   usaram cada cupom. Agrupamos por cupom e calculamos o total
--   de descontos concedidos e a quantidade de usos.
-- ============================================================

SELECT
    c.code                                      AS cupom,
    c.type                                      AS tipo,
    c.value                                     AS valor_cupom,
    COUNT(o.id)                                 AS vezes_usado,
    COUNT(DISTINCT o."userId")                  AS clientes_distintos,
    ROUND(SUM(o.discount)::NUMERIC, 2)         AS total_desconto_dado,
    ROUND(AVG(o.total)::NUMERIC, 2)            AS ticket_medio
FROM "Coupon" c
INNER JOIN "Order" o  ON o."couponCode" = c.code
INNER JOIN "User" u   ON u.id = o."userId"
WHERE o.status != 'cancelado'
GROUP BY c.id, c.code, c.type, c.value
ORDER BY vezes_usado DESC;
