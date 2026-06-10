-- ============================================================
-- QUERY 08: Produtos na Wishlist que o Cliente Ainda Não Comprou
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Quais produtos estão na lista de desejos dos clientes
--   mas ainda não foram comprados por eles? Oportunidade
--   para enviar promoções direcionadas.
--
-- TABELAS ENVOLVIDAS (4):
--   Wishlist, User, Product, OrderItem
--
-- TÉCNICA: NOT EXISTS com subquery correlacionada
--
-- EXPLICAÇÃO:
--   Para cada item na Wishlist, verificamos se o mesmo usuário
--   já comprou aquele produto. Usamos NOT EXISTS com uma subquery
--   que busca em OrderItem (via Order) se existe algum pedido
--   daquele usuário contendo aquele produto. Se não existe,
--   significa que o cliente deseja mas ainda não comprou.
--   NOT EXISTS é mais eficiente que NOT IN para este tipo de
--   verificação quando há possibilidade de NULLs.
-- ============================================================

SELECT
    u."displayName"     AS cliente,
    u.email             AS email,
    p.name              AS produto_desejado,
    p.price             AS preco,
    w."createdAt"       AS adicionado_em
FROM "Wishlist" w
INNER JOIN "User" u    ON u.id = w."userId"
INNER JOIN "Product" p ON p.id = w."productId"
WHERE NOT EXISTS (
    SELECT 1
    FROM "OrderItem" oi
    INNER JOIN "Order" o ON o.id = oi."orderId"
    WHERE o."userId" = w."userId"
      AND oi."productId" = w."productId"
      AND o.status != 'cancelado'
)
ORDER BY w."createdAt" DESC
LIMIT 20;
