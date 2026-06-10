-- ============================================================
-- FutStore — Linguagem Procedural (PL/pgSQL)
-- Procedures, Functions e Triggers
-- ============================================================

-- ============================================================
-- 1. FUNCTION: fn_calcular_total
-- Calcula o total de um pedido dado um array de itens (JSON)
-- e um código de cupom opcional.
-- Retorna o valor total com desconto aplicado.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_calcular_total(
    p_items JSONB,
    p_cupom_code TEXT DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_subtotal NUMERIC := 0;
    v_desconto NUMERIC := 0;
    v_item JSONB;
    v_cupom RECORD;
    v_shipping NUMERIC := 25.00;
BEGIN
    -- Percorre cada item do JSON e soma preço * quantidade
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_subtotal := v_subtotal + (v_item->>'unitPrice')::NUMERIC * (v_item->>'quantity')::INT;
    END LOOP;

    -- Aplica cupom se fornecido
    IF p_cupom_code IS NOT NULL THEN
        SELECT * INTO v_cupom
        FROM "Coupon"
        WHERE code = p_cupom_code
          AND active = true
          AND "validUntil" > NOW();

        IF FOUND THEN
            IF v_cupom.type = 'percent' THEN
                v_desconto := v_subtotal * (v_cupom.value / 100.0);
            ELSE
                v_desconto := LEAST(v_cupom.value, v_subtotal);
            END IF;
            RAISE NOTICE 'Cupom % aplicado: desconto R$ %', p_cupom_code, v_desconto;
        ELSE
            RAISE NOTICE 'Cupom % inválido ou expirado — ignorado.', p_cupom_code;
        END IF;
    END IF;

    RETURN v_subtotal - v_desconto + v_shipping;
END;
$$;

-- ============================================================
-- 2. FUNCTION: fn_ranking_vendas
-- Retorna os N produtos mais vendidos com informações de
-- categoria e marca. Usa JOIN entre Product, Category e Brand.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_ranking_vendas(p_limite INT DEFAULT 10)
RETURNS TABLE(
    produto_id TEXT,
    nome TEXT,
    time_nome TEXT,
    categoria TEXT,
    marca TEXT,
    vendas INT,
    preco DOUBLE PRECISION
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.name,
        p.team,
        COALESCE(c.name, p.category),
        COALESCE(b.name, 'Sem marca'),
        p."salesCount",
        p.price
    FROM "Product" p
    LEFT JOIN "Category" c ON c.id = p."categoryId"
    LEFT JOIN "Brand" b ON b.id = p."brandId"
    WHERE p.active = true
    ORDER BY p."salesCount" DESC
    LIMIT p_limite;
END;
$$;

-- ============================================================
-- 3. PROCEDURE: sp_finalizar_pedido
-- Cria um pedido completo: valida estoque, decrementa,
-- registra Order + OrderItems + Payment.
-- Demonstra: BEGIN/EXCEPTION/RAISE/ROLLBACK conceitual.
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_finalizar_pedido(
    p_user_id TEXT,
    p_items JSONB,
    p_cupom_code TEXT DEFAULT NULL,
    p_endereco JSONB DEFAULT '{}',
    p_pagamento JSONB DEFAULT '{}'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_item JSONB;
    v_product RECORD;
    v_ps RECORD;
    v_subtotal NUMERIC := 0;
    v_desconto NUMERIC := 0;
    v_shipping NUMERIC := 25.00;
    v_total NUMERIC;
    v_order_id TEXT;
    v_cupom RECORD;
BEGIN
    RAISE NOTICE '=== Iniciando finalização de pedido para usuário % ===', p_user_id;

    -- Validação: usuário existe?
    IF NOT EXISTS (SELECT 1 FROM "User" WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'Usuário % não encontrado.', p_user_id;
    END IF;

    -- Validação: itens não vazios?
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Carrinho vazio — nenhum item informado.';
    END IF;

    -- Valida estoque de cada item
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT * INTO v_ps
        FROM "ProductSize"
        WHERE "productId" = (v_item->>'productId')
          AND size = (v_item->>'size');

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Produto/tamanho não encontrado: % / %',
                v_item->>'productId', v_item->>'size';
        END IF;

        IF v_ps.stock < (v_item->>'quantity')::INT THEN
            RAISE EXCEPTION 'Estoque insuficiente para produto % tamanho %. Disponível: %, solicitado: %',
                v_item->>'productId', v_item->>'size', v_ps.stock, v_item->>'quantity';
        END IF;

        v_subtotal := v_subtotal + (v_item->>'unitPrice')::NUMERIC * (v_item->>'quantity')::INT;
    END LOOP;

    -- Aplica cupom
    IF p_cupom_code IS NOT NULL THEN
        SELECT * INTO v_cupom FROM "Coupon"
        WHERE code = p_cupom_code AND active = true AND "validUntil" > NOW();

        IF FOUND THEN
            IF v_cupom.type = 'percent' THEN
                v_desconto := v_subtotal * (v_cupom.value / 100.0);
            ELSE
                v_desconto := LEAST(v_cupom.value, v_subtotal);
            END IF;
        END IF;
    END IF;

    v_total := v_subtotal - v_desconto + v_shipping;
    RAISE NOTICE 'Subtotal: R$ %, Desconto: R$ %, Frete: R$ %, Total: R$ %',
        v_subtotal, v_desconto, v_shipping, v_total;

    -- Gera ID do pedido
    v_order_id := gen_random_uuid()::TEXT;

    -- Cria o pedido (TCL: dentro da transação implícita do CALL)
    INSERT INTO "Order" (
        id, "userId", "couponCode", subtotal, discount, shipping, total,
        status, "paymentMethod",
        "addressFullName", "addressStreet", "addressNumber",
        "addressCity", "addressState", "addressZip",
        "statusHistory", "createdAt"
    ) VALUES (
        v_order_id, p_user_id, p_cupom_code, v_subtotal, v_desconto, v_shipping, v_total,
        'pago', COALESCE(p_pagamento->>'method', 'pix'),
        COALESCE(p_endereco->>'fullName', 'Cliente'),
        COALESCE(p_endereco->>'street', 'Rua Exemplo'),
        COALESCE(p_endereco->>'number', '100'),
        COALESCE(p_endereco->>'city', 'São Paulo'),
        COALESCE(p_endereco->>'state', 'SP'),
        COALESCE(p_endereco->>'zip', '01000000'),
        jsonb_build_array(jsonb_build_object('status', 'pago', 'at', NOW()::TEXT)),
        NOW()
    );

    -- Cria itens e decrementa estoque
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        -- Busca nome do produto para snapshot
        SELECT name INTO v_product FROM "Product" WHERE id = (v_item->>'productId');

        INSERT INTO "OrderItem" ("orderId", "productId", name, size, "unitPrice", quantity, "imageUrl")
        VALUES (
            v_order_id,
            v_item->>'productId',
            COALESCE(v_product.name, 'Produto'),
            v_item->>'size',
            (v_item->>'unitPrice')::DOUBLE PRECISION,
            (v_item->>'quantity')::INT,
            '/jerseys/placeholder.jpg'
        );

        -- Decrementa estoque
        UPDATE "ProductSize"
        SET stock = stock - (v_item->>'quantity')::INT
        WHERE "productId" = (v_item->>'productId')
          AND size = (v_item->>'size');

        -- Incrementa salesCount
        UPDATE "Product"
        SET "salesCount" = "salesCount" + (v_item->>'quantity')::INT
        WHERE id = (v_item->>'productId');

        RAISE NOTICE 'Item adicionado: % x % (tamanho %)',
            v_item->>'quantity', v_product.name, v_item->>'size';
    END LOOP;

    -- Cria pagamento
    INSERT INTO "Payment" (id, "orderId", method, amount, status, "paidAt")
    VALUES (
        gen_random_uuid()::TEXT,
        v_order_id,
        COALESCE(p_pagamento->>'method', 'pix'),
        v_total,
        'approved',
        NOW()
    );

    RAISE NOTICE '✅ Pedido % criado com sucesso! Total: R$ %', v_order_id, v_total;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Erro ao finalizar pedido: % — transação revertida (ROLLBACK).', SQLERRM;
END;
$$;

-- ============================================================
-- 4. TRIGGER FUNCTION + TRIGGER: trg_movimento_estoque
-- Quando o estoque de ProductSize é alterado (UPDATE),
-- registra automaticamente um StockMovement com a diferença.
-- Conceitos: NEW, OLD, AFTER trigger, INSERT automático.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_registrar_movimento_estoque()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_diff INT;
    v_tipo TEXT;
    v_motivo TEXT;
BEGIN
    v_diff := NEW.stock - OLD.stock;

    -- Só registra se houve mudança real no estoque
    IF v_diff = 0 THEN
        RETURN NEW;
    END IF;

    IF v_diff > 0 THEN
        v_tipo := 'in';
        v_motivo := 'Reposição de estoque';
    ELSE
        v_tipo := 'out';
        v_motivo := 'Saída por venda ou ajuste';
    END IF;

    INSERT INTO "StockMovement" ("productSizeId", type, quantity, reason, "createdAt")
    VALUES (NEW.id, v_tipo, ABS(v_diff), v_motivo, NOW());

    RAISE NOTICE 'Trigger: Movimento de estoque registrado — ProductSize %, tipo %, qtd %',
        NEW.id, v_tipo, ABS(v_diff);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_movimento_estoque ON "ProductSize";
CREATE TRIGGER trg_movimento_estoque
    AFTER UPDATE OF stock ON "ProductSize"
    FOR EACH ROW
    EXECUTE FUNCTION fn_registrar_movimento_estoque();

-- ============================================================
-- 5. TRIGGER FUNCTION + TRIGGER: trg_audit_log
-- Quando o status de um pedido (Order) é alterado,
-- registra automaticamente no AuditLog.
-- Conceitos: AFTER UPDATE, WHEN (condição), NEW vs OLD.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_audit_status_pedido()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO "AuditLog" ("userId", "tableName", action, payload, "createdAt")
    VALUES (
        NEW."userId",
        'Order',
        'UPDATE',
        jsonb_build_object(
            'orderId', NEW.id,
            'statusAnterior', OLD.status,
            'statusNovo', NEW.status,
            'alteradoEm', NOW()::TEXT
        ),
        NOW()
    );

    RAISE NOTICE 'Trigger: Auditoria registrada — Pedido % mudou de % para %',
        NEW.id, OLD.status, NEW.status;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_status_pedido ON "Order";
CREATE TRIGGER trg_audit_status_pedido
    AFTER UPDATE OF status ON "Order"
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION fn_audit_status_pedido();

-- ============================================================
-- Verificação: lista objetos criados
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Objetos PL/pgSQL criados com sucesso:';
    RAISE NOTICE '  - FUNCTION fn_calcular_total';
    RAISE NOTICE '  - FUNCTION fn_ranking_vendas';
    RAISE NOTICE '  - PROCEDURE sp_finalizar_pedido';
    RAISE NOTICE '  - TRIGGER trg_movimento_estoque';
    RAISE NOTICE '  - TRIGGER trg_audit_status_pedido';
    RAISE NOTICE '========================================';
END;
$$;
