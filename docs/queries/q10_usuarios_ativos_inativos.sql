-- ============================================================
-- QUERY 10: Classificação de Usuários (Ativos vs Inativos)
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Classificar os usuários em ativos (compraram nos últimos
--   90 dias), inativos (não compraram nos últimos 90 dias) e
--   novos (nunca compraram). Fundamental para estratégias de
--   retenção e reativação.
--
-- TABELAS ENVOLVIDAS (3):
--   User, Order, AuditLog
--
-- TÉCNICA: CTE (Common Table Expression) + CASE + LEFT JOIN
--
-- EXPLICAÇÃO:
--   Usamos CTE para primeiro calcular, para cada usuário,
--   a data do último pedido e o total de pedidos. Depois,
--   na query principal, usamos CASE WHEN para classificar
--   cada usuário como 'Ativo', 'Inativo' ou 'Novo'.
--   O LEFT JOIN com AuditLog conta as ações registradas
--   por cada usuário no sistema (logins, edições, etc.),
--   enriquecendo a visão de engajamento.
--   CTEs tornam queries complexas mais legíveis ao dividir
--   a lógica em blocos nomeados.
-- ============================================================

WITH resumo_usuario AS (
    SELECT
        u.id                            AS user_id,
        u."displayName"                 AS nome,
        u.email,
        u."createdAt"                   AS membro_desde,
        COUNT(o.id)                     AS total_pedidos,
        MAX(o."createdAt")              AS ultimo_pedido,
        COALESCE(SUM(o.total), 0)       AS total_gasto
    FROM "User" u
    LEFT JOIN "Order" o ON o."userId" = u.id AND o.status != 'cancelado'
    GROUP BY u.id, u."displayName", u.email, u."createdAt"
)
SELECT
    ru.nome,
    ru.email,
    ru.total_pedidos,
    ROUND(ru.total_gasto::NUMERIC, 2)  AS total_gasto,
    ru.ultimo_pedido,
    COUNT(al.id)                        AS acoes_no_sistema,
    CASE
        WHEN ru.total_pedidos = 0 THEN 'Novo'
        WHEN ru.ultimo_pedido >= NOW() - INTERVAL '90 days' THEN 'Ativo'
        ELSE 'Inativo'
    END AS classificacao
FROM resumo_usuario ru
LEFT JOIN "AuditLog" al ON al."userId" = ru.user_id
GROUP BY ru.user_id, ru.nome, ru.email, ru.total_pedidos,
         ru.total_gasto, ru.ultimo_pedido, ru.membro_desde
ORDER BY
    CASE
        WHEN ru.total_pedidos = 0 THEN 3
        WHEN ru.ultimo_pedido >= NOW() - INTERVAL '90 days' THEN 1
        ELSE 2
    END,
    ru.total_gasto DESC
LIMIT 30;
