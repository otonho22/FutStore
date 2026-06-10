-- ============================================================
-- QUERY 07: Detalhes Completos de um Pedido
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Dado um pedido, mostrar TODOS os detalhes: cliente, itens,
--   produto, endereço, pagamento. Visão 360° do pedido.
--
-- TABELAS ENVOLVIDAS (5):
--   Order, OrderItem, Product, User, Payment
--
-- TÉCNICA: JOIN extenso de 5 tabelas (maior JOIN do projeto)
--
-- EXPLICAÇÃO:
--   Esta é a consulta mais completa do sistema. Parte da tabela Order
--   e faz JOIN com:
--   - User: dados do cliente
--   - OrderItem: itens do pedido
--   - Product: informações completas do produto
--   - Payment: dados do pagamento
--   Mostra em uma única query toda a informação necessária para
--   atendimento ao cliente ou auditoria de pedido. Os 5 JOINs
--   demonstram a capacidade de unir múltiplas entidades relacionadas.
-- ============================================================

SELECT
    o.id                    AS pedido_id,
    o."createdAt"           AS data_pedido,
    o.status                AS status_pedido,
    u."displayName"         AS cliente,
    u.email                 AS email_cliente,
    oi.name                 AS produto,
    oi.size                 AS tamanho,
    oi.quantity             AS quantidade,
    oi."unitPrice"          AS preco_unitario,
    (oi."unitPrice" * oi.quantity) AS subtotal_item,
    p.team                  AS time,
    o."addressCity"         AS cidade_entrega,
    o."addressState"        AS estado_entrega,
    pay.method              AS forma_pagamento,
    pay.status              AS status_pagamento,
    pay.amount              AS valor_pago,
    o."trackingCode"        AS codigo_rastreio
FROM "Order" o
INNER JOIN "User" u       ON u.id = o."userId"
INNER JOIN "OrderItem" oi ON oi."orderId" = o.id
INNER JOIN "Product" p    ON p.id = oi."productId"
LEFT JOIN "Payment" pay   ON pay."orderId" = o.id
ORDER BY o."createdAt" DESC
LIMIT 20;
