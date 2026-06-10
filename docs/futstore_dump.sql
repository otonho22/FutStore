--
-- PostgreSQL database dump
--

\restrict otRxv2ahnFvlQVDgJjMaPpLVUx9N4QBn5dB3978cBxyhanERKYRgG1n632tYYqe

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: fn_audit_status_pedido(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_audit_status_pedido() RETURNS trigger
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


ALTER FUNCTION public.fn_audit_status_pedido() OWNER TO postgres;

--
-- Name: fn_calcular_total(jsonb, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_calcular_total(p_items jsonb, p_cupom_code text DEFAULT NULL::text) RETURNS numeric
    LANGUAGE plpgsql
    AS $_$
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
$_$;


ALTER FUNCTION public.fn_calcular_total(p_items jsonb, p_cupom_code text) OWNER TO postgres;

--
-- Name: fn_ranking_vendas(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_ranking_vendas(p_limite integer DEFAULT 10) RETURNS TABLE(produto_id text, nome text, time_nome text, categoria text, marca text, vendas integer, preco double precision)
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


ALTER FUNCTION public.fn_ranking_vendas(p_limite integer) OWNER TO postgres;

--
-- Name: fn_registrar_movimento_estoque(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_registrar_movimento_estoque() RETURNS trigger
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


ALTER FUNCTION public.fn_registrar_movimento_estoque() OWNER TO postgres;

--
-- Name: sp_finalizar_pedido(text, jsonb, text, jsonb, jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_finalizar_pedido(IN p_user_id text, IN p_items jsonb, IN p_cupom_code text DEFAULT NULL::text, IN p_endereco jsonb DEFAULT '{}'::jsonb, IN p_pagamento jsonb DEFAULT '{}'::jsonb)
    LANGUAGE plpgsql
    AS $_$
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
$_$;


ALTER PROCEDURE public.sp_finalizar_pedido(IN p_user_id text, IN p_items jsonb, IN p_cupom_code text, IN p_endereco jsonb, IN p_pagamento jsonb) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: Address; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Address" (
    id text NOT NULL,
    "userId" text NOT NULL,
    "fullName" text NOT NULL,
    street text NOT NULL,
    number text NOT NULL,
    complement text,
    city text NOT NULL,
    state text NOT NULL,
    zip text NOT NULL,
    "isDefault" boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."Address" OWNER TO postgres;

--
-- Name: AuditLog; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."AuditLog" (
    id integer NOT NULL,
    "userId" text,
    "tableName" text NOT NULL,
    action text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."AuditLog" OWNER TO postgres;

--
-- Name: AuditLog_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."AuditLog_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."AuditLog_id_seq" OWNER TO postgres;

--
-- Name: AuditLog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."AuditLog_id_seq" OWNED BY public."AuditLog".id;


--
-- Name: Brand; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Brand" (
    id text NOT NULL,
    name text NOT NULL,
    "logoUrl" text DEFAULT ''::text NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."Brand" OWNER TO postgres;

--
-- Name: Category; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Category" (
    id text NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."Category" OWNER TO postgres;

--
-- Name: Coupon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Coupon" (
    id text NOT NULL,
    code text NOT NULL,
    type text NOT NULL,
    value double precision NOT NULL,
    "validUntil" timestamp(3) without time zone NOT NULL,
    active boolean DEFAULT true NOT NULL,
    "firstPurchaseOnly" boolean DEFAULT false NOT NULL,
    "maxUsesPerCustomer" integer,
    "maxUsesGlobal" integer,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."Coupon" OWNER TO postgres;

--
-- Name: Order; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Order" (
    id text NOT NULL,
    "userId" text NOT NULL,
    "userEmail" text,
    "couponCode" text,
    subtotal double precision NOT NULL,
    discount double precision DEFAULT 0 NOT NULL,
    shipping double precision DEFAULT 0 NOT NULL,
    total double precision NOT NULL,
    status text DEFAULT 'pendente'::text NOT NULL,
    "trackingCode" text,
    "paymentMethod" text DEFAULT 'credit_card'::text NOT NULL,
    "paymentBrand" text,
    "paymentLast4" text,
    "paymentHolderName" text,
    "addressFullName" text NOT NULL,
    "addressStreet" text NOT NULL,
    "addressNumber" text NOT NULL,
    "addressComplement" text,
    "addressCity" text NOT NULL,
    "addressState" text NOT NULL,
    "addressZip" text NOT NULL,
    "statusHistory" jsonb DEFAULT '[]'::jsonb NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."Order" OWNER TO postgres;

--
-- Name: OrderItem; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."OrderItem" (
    id integer NOT NULL,
    "orderId" text NOT NULL,
    "productId" text NOT NULL,
    name text NOT NULL,
    size text NOT NULL,
    "unitPrice" double precision NOT NULL,
    quantity integer NOT NULL,
    "imageUrl" text
);


ALTER TABLE public."OrderItem" OWNER TO postgres;

--
-- Name: OrderItem_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."OrderItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."OrderItem_id_seq" OWNER TO postgres;

--
-- Name: OrderItem_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."OrderItem_id_seq" OWNED BY public."OrderItem".id;


--
-- Name: Payment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Payment" (
    id text NOT NULL,
    "orderId" text NOT NULL,
    method text NOT NULL,
    brand text,
    last4 text,
    "holderName" text,
    amount double precision NOT NULL,
    status text DEFAULT 'approved'::text NOT NULL,
    "paidAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."Payment" OWNER TO postgres;

--
-- Name: Product; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Product" (
    id text NOT NULL,
    name text NOT NULL,
    team text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    price double precision NOT NULL,
    "imageUrl" text NOT NULL,
    images text[] DEFAULT ARRAY[]::text[],
    category text NOT NULL,
    "salesCount" integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "brandId" text,
    "categoryId" text
);


ALTER TABLE public."Product" OWNER TO postgres;

--
-- Name: ProductSize; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."ProductSize" (
    id integer NOT NULL,
    "productId" text NOT NULL,
    size text NOT NULL,
    stock integer DEFAULT 0 NOT NULL,
    "minStock" integer DEFAULT 3 NOT NULL
);


ALTER TABLE public."ProductSize" OWNER TO postgres;

--
-- Name: ProductSize_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."ProductSize_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."ProductSize_id_seq" OWNER TO postgres;

--
-- Name: ProductSize_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."ProductSize_id_seq" OWNED BY public."ProductSize".id;


--
-- Name: Review; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Review" (
    id text NOT NULL,
    "productId" text NOT NULL,
    "userId" text NOT NULL,
    rating integer NOT NULL,
    comment text DEFAULT ''::text NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."Review" OWNER TO postgres;

--
-- Name: StockMovement; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."StockMovement" (
    id integer NOT NULL,
    "productSizeId" integer NOT NULL,
    type text NOT NULL,
    quantity integer NOT NULL,
    reason text DEFAULT ''::text NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."StockMovement" OWNER TO postgres;

--
-- Name: StockMovement_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."StockMovement_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."StockMovement_id_seq" OWNER TO postgres;

--
-- Name: StockMovement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."StockMovement_id_seq" OWNED BY public."StockMovement".id;


--
-- Name: User; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."User" (
    id text NOT NULL,
    email text NOT NULL,
    "displayName" text,
    role text DEFAULT 'customer'::text NOT NULL,
    "acceptedTerms" boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."User" OWNER TO postgres;

--
-- Name: Wishlist; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Wishlist" (
    id text NOT NULL,
    "userId" text NOT NULL,
    "productId" text NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."Wishlist" OWNER TO postgres;

--
-- Name: _prisma_migrations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public._prisma_migrations (
    id character varying(36) NOT NULL,
    checksum character varying(64) NOT NULL,
    finished_at timestamp with time zone,
    migration_name character varying(255) NOT NULL,
    logs text,
    rolled_back_at timestamp with time zone,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    applied_steps_count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public._prisma_migrations OWNER TO postgres;

--
-- Name: AuditLog id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."AuditLog" ALTER COLUMN id SET DEFAULT nextval('public."AuditLog_id_seq"'::regclass);


--
-- Name: OrderItem id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."OrderItem" ALTER COLUMN id SET DEFAULT nextval('public."OrderItem_id_seq"'::regclass);


--
-- Name: ProductSize id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."ProductSize" ALTER COLUMN id SET DEFAULT nextval('public."ProductSize_id_seq"'::regclass);


--
-- Name: StockMovement id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."StockMovement" ALTER COLUMN id SET DEFAULT nextval('public."StockMovement_id_seq"'::regclass);


--
-- Data for Name: Address; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Address" (id, "userId", "fullName", street, number, complement, city, state, zip, "isDefault", "createdAt") FROM stdin;
cmq848inw006elz656gbucn1a	user_001	Sr. Benjamin Pereira	Alameda Rebeca	9734	\N	Albuquerque do Descoberto	PR	47642944	t	2026-06-10 13:39:56.157
cmq848inz006glz65hk6mph6w	user_001	Srta. Mércia Carvalho	Avenida Melo	9436	\N	Xavier de Nossa Senhora	MA	22063849	f	2026-06-10 13:39:56.16
cmq848io0006ilz656dren9dm	user_001	Rebeca Santos	Alameda Souza	6166	\N	Bruna do Norte	PE	24052734	f	2026-06-10 13:39:56.161
cmq848io1006klz65d9at7khh	user_002	Isis Nogueira	Rodovia Moraes	1050	Apto 494	Maria Alice do Norte	DF	03503003	t	2026-06-10 13:39:56.161
cmq848io2006mlz65l6itgknn	user_003	Nataniel Carvalho Jr.	Marginal Barros	5413	\N	Macedo do Sul	RJ	85846570	t	2026-06-10 13:39:56.162
cmq848io2006olz65ya6f3rup	user_004	Cecília Carvalho	Avenida Matheus	4982	\N	Xavier do Norte	MG	60024877	t	2026-06-10 13:39:56.163
cmq848io3006qlz65dl269854	user_005	Isadora Albuquerque	Travessa Silva	9007	\N	Vitor do Descoberto	GO	67179129	t	2026-06-10 13:39:56.163
cmq848io4006slz65gvywjbms	user_005	Rafaela Costa	Alameda Margarida	1636	Apto 485	Felipe do Sul	RJ	94201538	f	2026-06-10 13:39:56.164
cmq848io4006ulz65j5i2wiup	user_006	Maria Braga Jr.	Alameda Santos	5853	\N	Fabrícia do Descoberto	CE	90149350	t	2026-06-10 13:39:56.165
cmq848io5006wlz653e8slu2b	user_006	Vitória Albuquerque	Rodovia Moraes	6668	Apto 15	Davi do Norte	ES	06481689	f	2026-06-10 13:39:56.165
cmq848io6006ylz65h8qot5rh	user_007	Srta. Maria Alice Moreira	Marginal Martins	6512	Apto 329	Martins do Sul	PA	57843687	t	2026-06-10 13:39:56.166
cmq848io60070lz65c99cxn78	user_007	Henrique Batista	Avenida Janaína	6954	Apto 225	Eloá do Descoberto	GO	66438540	f	2026-06-10 13:39:56.167
cmq848io70072lz65unowqran	user_008	Janaína Moreira	Marginal Albuquerque	1958	Apto 324	Barros do Sul	BA	14223853	t	2026-06-10 13:39:56.167
cmq848io70074lz6566j8sz1a	user_009	Enzo Batista Filho	Alameda Bryan	5673	Apto 482	Júlio César do Descoberto	GO	96882264	t	2026-06-10 13:39:56.168
cmq848io80076lz65oikw1e77	user_009	Vicente Carvalho	Marginal Maria Helena	956	\N	César do Norte	AM	20066523	f	2026-06-10 13:39:56.169
cmq848io90078lz65eqaf7oi1	user_010	Yasmin Pereira	Marginal Ígor	1284	Apto 363	Barros do Sul	MG	32305082	t	2026-06-10 13:39:56.169
cmq848io9007alz650ye801zr	user_010	Tertuliano Moreira	Marginal Miguel	5578	\N	Maitê do Sul	MG	62504736	f	2026-06-10 13:39:56.17
cmq848ioa007clz65nqb3a4qk	user_011	Eduardo Braga	Alameda Oliveira	892	\N	Pietro do Norte	SP	32309533	t	2026-06-10 13:39:56.171
cmq848ioc007elz653t77kkbl	user_011	Margarida Souza	Rodovia Batista	8174	Apto 439	Franco do Descoberto	PE	16396818	f	2026-06-10 13:39:56.172
cmq848ioe007glz65ondugdgv	user_012	Maria Braga	Rua Ana Júlia	259	Apto 482	Franco do Norte	PE	16266107	t	2026-06-10 13:39:56.174
cmq848iof007ilz65tj3ezqcu	user_012	Ana Clara Barros	Avenida Franco	1011	\N	Ígor do Sul	GO	36541841	f	2026-06-10 13:39:56.176
cmq848ioi007klz651j9q705c	user_012	Joana Reis	Travessa Alice	2598	\N	Davi Lucca do Descoberto	RS	98941548	f	2026-06-10 13:39:56.178
cmq848iok007mlz653by76n5y	user_013	Cecília Reis	Travessa Márcia	8920	\N	Melo de Nossa Senhora	AM	09466866	t	2026-06-10 13:39:56.181
cmq848iol007olz659parsw1b	user_014	Cauã Moraes	Rua Benício	713	Apto 479	Macedo do Sul	GO	11067200	t	2026-06-10 13:39:56.182
cmq848iom007qlz65hv31wqxk	user_015	Morgana Martins	Alameda Marcos	5303	Apto 485	Nogueira do Norte	PA	86139234	t	2026-06-10 13:39:56.183
cmq848ion007slz65jpvq483t	user_015	Maria Costa Jr.	Alameda Silva	8465	\N	Hélio do Sul	SC	76159901	f	2026-06-10 13:39:56.183
cmq848ioo007ulz65dl9k4iio	user_015	Marina Carvalho	Marginal Moraes	2976	\N	Reis do Descoberto	PE	02790482	f	2026-06-10 13:39:56.184
cmq848iop007wlz65liw7o8m3	user_016	Lucca Macedo	Rua Reis	2025	\N	Cecília de Nossa Senhora	MA	93478534	t	2026-06-10 13:39:56.185
cmq848ioq007ylz656bzvja90	user_016	Alessandro Macedo	Alameda Maria Clara	649	\N	Pereira do Sul	PR	84003777	f	2026-06-10 13:39:56.186
cmq848ios0080lz654a23b4xx	user_017	Dra. Carla Melo	Marginal Oliveira	4213	\N	Saraiva de Nossa Senhora	DF	51330082	t	2026-06-10 13:39:56.188
cmq848iot0082lz65iafejvxm	user_017	Fabrício Costa	Rodovia Melo	4830	Apto 41	Reis do Sul	MG	61769002	f	2026-06-10 13:39:56.189
cmq848iot0084lz658l63ot3a	user_018	Sarah Costa	Marginal Lavínia	337	Apto 454	Gúbio de Nossa Senhora	MA	06959042	t	2026-06-10 13:39:56.19
cmq848iou0086lz65w7ps6jcq	user_019	Emanuel Carvalho	Rodovia Fábio	1141	Apto 113	Kléber do Norte	RJ	87075044	t	2026-06-10 13:39:56.19
cmq848iou0088lz6520fad0yg	user_019	Sílvia Pereira	Alameda Benjamin	5125	\N	Márcia do Descoberto	RS	13752888	f	2026-06-10 13:39:56.191
cmq848iov008alz65106qaqa9	user_020	Sra. Vitória Albuquerque	Alameda Oliveira	8221	Apto 388	Franco do Sul	DF	67395167	t	2026-06-10 13:39:56.191
cmq848iov008clz65hq2lmqoy	user_021	Vicente Xavier Jr.	Rodovia Cauã	4403	\N	Raul do Norte	ES	49661841	t	2026-06-10 13:39:56.192
cmq848iow008elz65zvfyscyc	user_022	Sr. João Pedro Silva	Rodovia Júlio	7102	Apto 236	Moraes do Sul	BA	17812134	t	2026-06-10 13:39:56.193
cmq848iox008glz654xgflf6o	user_023	Lucca Saraiva	Alameda Franco	6863	Apto 88	Costa do Norte	SC	53203698	t	2026-06-10 13:39:56.194
cmq848ioy008ilz65ph3myyxi	user_023	Rafael Costa	Alameda Melo	8645	\N	Bryan de Nossa Senhora	SP	79282978	f	2026-06-10 13:39:56.194
cmq848ioz008klz65bdzp5ban	user_024	Norberto Saraiva	Rua Batista	2419	Apto 235	Fabrício de Nossa Senhora	PA	09865810	t	2026-06-10 13:39:56.195
cmq848ip0008mlz65ushl78ic	user_025	Antônio Xavier	Rua Batista	939	\N	Nogueira do Norte	PE	34768466	t	2026-06-10 13:39:56.197
cmq848ip1008olz65n2e1a3ee	user_026	Eduardo Batista	Alameda Lorenzo	7436	\N	Macedo de Nossa Senhora	SP	12934162	t	2026-06-10 13:39:56.197
cmq848ip2008qlz6584sjblkh	user_026	Lorena Albuquerque	Rua Natália	5720	\N	Guilherme do Descoberto	GO	13584791	f	2026-06-10 13:39:56.198
cmq848ip2008slz65f4bsbhxd	user_027	Júlia Souza	Avenida Saraiva	16	\N	Ana Clara do Norte	SC	13431470	t	2026-06-10 13:39:56.199
cmq848ip3008ulz65euh0coz2	user_028	Sílvia Pereira	Rua Nogueira	8737	\N	Benjamin do Norte	MG	04245015	t	2026-06-10 13:39:56.2
cmq848ip4008wlz65kw4xp51r	user_029	Matheus Pereira	Avenida Melo	7984	\N	Franco do Norte	BA	67631418	t	2026-06-10 13:39:56.2
cmq848ip5008ylz653p5syg8h	user_030	Aline Oliveira	Travessa Maria Helena	6058	Apto 109	Batista de Nossa Senhora	SP	59300310	t	2026-06-10 13:39:56.201
cmq848ip60090lz65av7m6fmg	user_031	Giovanna Batista	Rodovia Roberto	9840	Apto 481	Isabela do Norte	MG	55784321	t	2026-06-10 13:39:56.202
cmq848ip70092lz65tyjusaok	user_031	Isabela Xavier	Alameda Karla	6262	\N	Tertuliano do Norte	DF	62304529	f	2026-06-10 13:39:56.203
cmq848ip80094lz655zlellew	user_032	João Pedro Batista	Marginal Roberta	9440	Apto 232	Nogueira de Nossa Senhora	PR	27354589	t	2026-06-10 13:39:56.205
cmq848ipa0096lz65ywh4nwoh	user_032	Ofélia Nogueira	Rua Henrique	8469	\N	Hugo do Norte	GO	90467612	f	2026-06-10 13:39:56.206
cmq848ipb0098lz656zgnnizd	user_032	Natália Carvalho	Rodovia Roberto	2946	Apto 369	Reis do Sul	GO	78604044	f	2026-06-10 13:39:56.208
cmq848ipc009alz65pech61s4	user_033	Srta. Antonella Souza	Avenida Santos	7071	Apto 37	Eloá de Nossa Senhora	AM	94934269	t	2026-06-10 13:39:56.209
cmq848ipd009clz657qya58ly	user_034	Maria Clara Silva	Alameda Benício	6826	Apto 357	Moraes do Descoberto	PA	24216073	t	2026-06-10 13:39:56.209
cmq848ipe009elz65unb8yip2	user_034	Lorena Costa	Rodovia Emanuelly	7409	Apto 51	Paula de Nossa Senhora	PA	84939064	f	2026-06-10 13:39:56.21
cmq848ipe009glz658kezxk4y	user_035	Nicolas Braga	Rodovia Pereira	2981	Apto 391	Xavier do Norte	PE	42330748	t	2026-06-10 13:39:56.211
cmq848ipf009ilz659l9drjed	user_036	Maria Eduarda Silva	Alameda Oliveira	7386	Apto 323	Davi do Sul	PR	30152803	t	2026-06-10 13:39:56.211
cmq848ipf009klz65jx5v4oi0	user_036	Alice Martins	Alameda Alessandro	4641	\N	Santos do Sul	CE	91078120	f	2026-06-10 13:39:56.212
cmq848ipg009mlz65vvbfneuw	user_036	Morgana Macedo	Avenida Yango	8470	Apto 450	Martins de Nossa Senhora	SP	22474099	f	2026-06-10 13:39:56.213
cmq848iph009olz65jna8q4sg	user_037	Júlio Barros	Avenida Maria Alice	7813	\N	Marcelo de Nossa Senhora	SC	23924870	t	2026-06-10 13:39:56.213
cmq848iph009qlz6516kt17lk	user_037	Alessandra Melo Filho	Avenida Barros	2747	\N	Henrique do Descoberto	MG	42089782	f	2026-06-10 13:39:56.214
cmq848ipi009slz656xfp4i0r	user_038	Talita Pereira	Avenida Barros	6223	\N	Vicente do Sul	ES	59714726	t	2026-06-10 13:39:56.214
cmq848ipi009ulz65fm6vbsuq	user_038	César Santos	Rua Suélen	2287	\N	Paula do Norte	RJ	40461239	f	2026-06-10 13:39:56.215
cmq848ipj009wlz65j211gigc	user_038	Antônio Macedo	Rodovia Macedo	7875	Apto 283	Elísio do Descoberto	MA	15200182	f	2026-06-10 13:39:56.215
cmq848ipk009ylz6522rg1lh7	user_039	Henrique Moraes	Travessa Washington	8925	\N	Carvalho do Norte	MG	38200954	t	2026-06-10 13:39:56.216
cmq848ipk00a0lz650dh3t353	user_039	Salvador Pereira	Rua Costa	4252	Apto 64	Moraes do Descoberto	ES	23320792	f	2026-06-10 13:39:56.217
cmq848ipl00a2lz65g8g6xy85	user_039	Paulo Martins	Marginal Daniel	3710	\N	Martins do Norte	GO	05717590	f	2026-06-10 13:39:56.217
cmq848ipm00a4lz65n5ad50g7	user_040	Fabrício Reis Neto	Travessa Pereira	7143	\N	Silva de Nossa Senhora	AM	13398775	t	2026-06-10 13:39:56.218
cmq848ipn00a6lz65tu0q7du6	user_041	Isadora Santos	Rua Alexandre	7037	\N	Mariana do Sul	DF	90578185	t	2026-06-10 13:39:56.219
cmq848ipo00a8lz6501ve7gsh	user_041	Bruna Braga	Rodovia Raul	2505	\N	Albuquerque do Norte	SP	52336374	f	2026-06-10 13:39:56.22
cmq848ipp00aalz655xtdnmov	user_041	Márcia Melo	Rua Sílvia	6417	\N	Reis do Descoberto	PR	24905191	f	2026-06-10 13:39:56.221
cmq848ipq00aclz6562syg1ni	user_042	Noah Macedo	Avenida Fabrícia	2875	\N	Barros do Sul	PR	05662092	t	2026-06-10 13:39:56.222
cmq848ipq00aelz65xb0t80fg	user_042	Noah Franco	Rodovia Braga	9447	\N	Pereira do Norte	PE	05249381	f	2026-06-10 13:39:56.223
cmq848ipr00aglz65iz1hxc62	user_043	Sr. Breno Melo	Travessa Reis	91	\N	Pereira do Descoberto	MG	87022220	t	2026-06-10 13:39:56.223
cmq848ipr00ailz6516apjgd2	user_043	Srta. Marli Pereira	Marginal Moreira	2003	\N	Barros de Nossa Senhora	MA	55238674	f	2026-06-10 13:39:56.224
cmq848ips00aklz65d2qv7bmi	user_044	Mariana Melo	Rua Melo	220	Apto 252	Suélen do Descoberto	PA	46211016	t	2026-06-10 13:39:56.224
cmq848ips00amlz653wrns9xl	user_044	Ricardo Batista	Avenida Júlio	3569	Apto 415	Xavier de Nossa Senhora	BA	59813551	f	2026-06-10 13:39:56.225
cmq848ipt00aolz658wfq457o	user_045	Salvador Reis	Rua Pereira	2296	Apto 83	Pablo do Norte	MG	00182312	t	2026-06-10 13:39:56.225
cmq848ipu00aqlz65p62ypu7e	user_045	Lucas Barros	Avenida Lucca	5569	\N	Nicolas do Norte	MG	54865161	f	2026-06-10 13:39:56.226
cmq848ipu00aslz65iixqggsx	user_045	Carla Carvalho	Avenida Albuquerque	7927	Apto 238	Costa do Descoberto	SC	58884374	f	2026-06-10 13:39:56.227
cmq848ipv00aulz6555z1sl2i	user_046	Tertuliano Barros	Rodovia Silva	3894	\N	Barros de Nossa Senhora	AM	49532330	t	2026-06-10 13:39:56.228
cmq848ipw00awlz65annysuxx	user_047	Dra. Marina Pereira	Travessa Santos	5484	Apto 384	Santos do Norte	MG	66711879	t	2026-06-10 13:39:56.228
cmq848ipw00aylz65xcoeviqk	user_048	Matheus Nogueira	Travessa Enzo	2023	Apto 121	Sarah do Norte	MG	06386726	t	2026-06-10 13:39:56.229
cmq848ipx00b0lz65xy8sc3sd	user_048	Sílvia Franco	Marginal Margarida	2647	\N	Braga do Descoberto	SC	34020825	f	2026-06-10 13:39:56.229
cmq848ipx00b2lz6517b488vn	user_049	Felipe Silva	Rodovia Costa	5767	Apto 48	Santos do Sul	ES	20410375	t	2026-06-10 13:39:56.23
cmq848ipy00b4lz65phq20e6i	user_050	Eduardo Santos	Rua Moreira	6246	\N	Reis de Nossa Senhora	SC	32599352	t	2026-06-10 13:39:56.23
cmq848ipy00b6lz650d1dwlqm	user_051	Matheus Reis	Travessa Murilo	3731	\N	Nataniel do Norte	GO	21651746	t	2026-06-10 13:39:56.231
cmq848ipz00b8lz65phadx170	user_051	César Santos	Rodovia Moreira	4885	\N	Enzo Gabriel do Sul	DF	53004068	f	2026-06-10 13:39:56.231
cmq848ipz00balz656lqogsn4	user_051	Matheus Silva	Marginal Natália	9972	Apto 449	Saraiva do Descoberto	BA	09889030	f	2026-06-10 13:39:56.232
cmq848iq000bclz659favfgm7	user_052	Larissa Batista Jr.	Marginal Costa	7983	Apto 150	Esther de Nossa Senhora	SC	02813810	t	2026-06-10 13:39:56.232
cmq848iq000belz65k87p8kjm	user_053	Maitê Batista	Rua Moraes	823	\N	Benjamin de Nossa Senhora	PE	75678358	t	2026-06-10 13:39:56.233
cmq848iq100bglz65e1shmn4k	user_053	Théo Carvalho	Travessa Macedo	8598	\N	Melissa do Descoberto	MG	91554625	f	2026-06-10 13:39:56.233
cmq848iq200bilz65htkm0jhp	user_054	Carlos Braga	Avenida Fabiano	9271	\N	Santos de Nossa Senhora	RJ	58716228	t	2026-06-10 13:39:56.234
cmq848iq300bklz65yzdi866r	user_055	Alessandra Santos	Rua Barros	4861	\N	Eduarda do Descoberto	MA	44714459	t	2026-06-10 13:39:56.235
cmq848iq400bmlz65a0adczjq	user_056	Ofélia Albuquerque	Alameda Vitor	5099	\N	Lívia de Nossa Senhora	AM	10420716	t	2026-06-10 13:39:56.236
cmq848iq500bolz654ir5w70n	user_056	Célia Santos	Rua Pereira	5658	\N	Alice do Sul	CE	72309692	f	2026-06-10 13:39:56.237
cmq848iq500bqlz65f882b8qr	user_057	Feliciano Souza	Avenida Albuquerque	7160	\N	Macedo do Descoberto	PE	23891390	t	2026-06-10 13:39:56.238
cmq848iq600bslz65agff50ha	user_057	Clara Braga	Alameda Laura	6619	\N	Saraiva do Sul	SP	02644889	f	2026-06-10 13:39:56.239
cmq848iq700bulz65p85c887g	user_058	Enzo Braga	Marginal Marli	5315	Apto 247	Henrique do Descoberto	RJ	59376985	t	2026-06-10 13:39:56.239
cmq848iq800bwlz656tgfv6h6	user_059	Gustavo Albuquerque	Rua Batista	9805	Apto 34	Oliveira do Norte	RJ	15298929	t	2026-06-10 13:39:56.24
cmq848iq800bylz65u5iqsv49	user_059	Isabella Barros	Avenida Emanuel	5776	Apto 412	Macedo do Sul	PR	20448238	f	2026-06-10 13:39:56.241
cmq848iq900c0lz658hqxhrsc	user_060	Larissa Souza Filho	Alameda Martins	1613	\N	Barros de Nossa Senhora	RJ	69603548	t	2026-06-10 13:39:56.241
cmq848iqa00c2lz65ingur2w5	user_060	Lucas Costa Neto	Marginal Benício	3953	Apto 79	Braga do Sul	DF	25792899	f	2026-06-10 13:39:56.242
cmq848iqa00c4lz655g1grxou	user_060	Marcelo Reis	Travessa Braga	8329	\N	Souza de Nossa Senhora	AM	45353020	f	2026-06-10 13:39:56.243
cmq848iqb00c6lz65ipfzg2im	user_061	Guilherme Macedo	Rodovia Costa	9903	Apto 302	Souza do Descoberto	GO	23541147	t	2026-06-10 13:39:56.244
cmq848iqc00c8lz65nt3kq3b6	user_061	Sr. Bernardo Batista	Rua Saraiva	9746	Apto 116	Barros do Descoberto	DF	30507305	f	2026-06-10 13:39:56.244
cmq848iqc00calz656fg359a5	user_061	Valentina Costa	Rodovia Lívia	506	\N	Carvalho do Sul	MA	04380270	f	2026-06-10 13:39:56.245
cmq848iqd00cclz65t4wfooqz	user_062	Isabela Moreira Neto	Marginal Costa	3611	\N	Martins do Norte	MG	62882242	t	2026-06-10 13:39:56.245
cmq848iqd00celz65vp646mz7	user_062	Roberto Saraiva	Marginal Maria Helena	2707	Apto 497	Yuri do Sul	GO	58246443	f	2026-06-10 13:39:56.246
cmq848iqe00cglz65gst0toyj	user_063	Davi Pereira	Marginal Albuquerque	8899	\N	Melissa de Nossa Senhora	AM	11968365	t	2026-06-10 13:39:56.246
cmq848iqf00cilz65mpn7y8to	user_063	Nataniel Melo	Avenida Oliveira	7471	Apto 30	Samuel do Descoberto	PA	34934002	f	2026-06-10 13:39:56.247
cmq848iqf00cklz659dwj0yhh	user_064	Heitor Braga	Rodovia Nogueira	5639	\N	Margarida de Nossa Senhora	MA	41725697	t	2026-06-10 13:39:56.248
cmq848iqg00cmlz653oq4uq3p	user_065	Washington Albuquerque	Alameda Lorenzo	163	\N	Júlio César de Nossa Senhora	MG	08961477	t	2026-06-10 13:39:56.248
cmq848iqg00colz65j9lihgyf	user_065	Alessandra Macedo	Alameda Yago	5657	\N	Gael do Norte	BA	20301945	f	2026-06-10 13:39:56.249
cmq848iqh00cqlz659am1efnd	user_066	Leonardo Franco	Marginal Feliciano	1332	\N	Nicolas do Norte	PA	84761024	t	2026-06-10 13:39:56.249
cmq848iqh00cslz65kmp9gzzo	user_066	Samuel Batista	Travessa Júlio	861	Apto 53	Oliveira do Sul	SP	46236885	f	2026-06-10 13:39:56.25
cmq848iqi00culz65bfk1iece	user_066	Gabriel Melo Filho	Travessa Franco	569	\N	Martins do Sul	PE	49215930	f	2026-06-10 13:39:56.25
cmq848iqi00cwlz65eccsyiez	user_067	César Xavier	Travessa Roberta	4148	Apto 330	Benjamin do Sul	ES	69146543	t	2026-06-10 13:39:56.251
cmq848iqj00cylz65ss0tj6bo	user_068	Sra. Clara Carvalho	Rodovia Santos	5403	Apto 283	Braga do Descoberto	PE	50975804	t	2026-06-10 13:39:56.251
cmq848iqk00d0lz65w4f70bi3	user_069	Pietro Souza Filho	Avenida Martins	5163	\N	Saraiva do Sul	SP	90821463	t	2026-06-10 13:39:56.253
cmq848iql00d2lz65l98p2rgy	user_069	Margarida Martins	Rua Roberto	5880	Apto 400	Santos do Norte	PE	95626510	f	2026-06-10 13:39:56.254
cmq848iqm00d4lz654gntt8vj	user_070	Dr. João Pedro Oliveira	Avenida Isis	512	Apto 256	Ofélia do Descoberto	CE	00558590	t	2026-06-10 13:39:56.254
cmq848iqn00d6lz65mo5kopj9	user_070	Alícia Moreira	Rodovia Fabrício	772	Apto 64	Elísio de Nossa Senhora	ES	69135006	f	2026-06-10 13:39:56.255
cmq848iqn00d8lz65jt2vy4ih	user_071	Lavínia Albuquerque	Rua Lorenzo	7286	Apto 197	Célia do Sul	SC	54902379	t	2026-06-10 13:39:56.256
cmq848iqo00dalz653kujoyqj	user_071	Rebeca Carvalho	Rodovia Mércia	3342	\N	Salvador do Sul	AM	06145459	f	2026-06-10 13:39:56.256
cmq848iqp00dclz6541loell2	user_072	Guilherme Braga	Rodovia Macedo	6692	\N	Margarida do Norte	MG	45527037	t	2026-06-10 13:39:56.257
cmq848iqp00delz65fz9svhgp	user_073	Maria Luiza Santos	Travessa Martins	5993	\N	Liz de Nossa Senhora	PA	05914065	t	2026-06-10 13:39:56.258
cmq848iqq00dglz65k2sztqbg	user_073	Srta. Lorraine Carvalho	Rodovia Melo	7498	\N	Carvalho do Descoberto	PR	55460015	f	2026-06-10 13:39:56.258
cmq848iqr00dilz65du748hrp	user_074	Janaína Albuquerque	Marginal Braga	8861	\N	Souza do Sul	SC	28028221	t	2026-06-10 13:39:56.259
cmq848iqr00dklz65iz9p824z	user_075	Murilo Reis	Travessa Vitória	6456	\N	Pedro Henrique do Norte	ES	31675253	t	2026-06-10 13:39:56.26
cmq848iqs00dmlz65b1q3vss9	user_075	Maria Clara Carvalho	Avenida Vitor	3702	\N	Xavier de Nossa Senhora	BA	04123883	f	2026-06-10 13:39:56.26
cmq848iqs00dolz651js9ku52	user_075	Silas Braga	Marginal Oliveira	5106	Apto 157	Xavier de Nossa Senhora	GO	78938177	f	2026-06-10 13:39:56.261
cmq848iqt00dqlz653e5x1kjr	user_076	Rebeca Barros	Rodovia Clara	8364	\N	João Lucas do Norte	PE	88718663	t	2026-06-10 13:39:56.262
cmq848iqu00dslz65xpr3ccha	user_076	Norberto Martins	Rodovia Marcelo	2706	Apto 472	Guilherme do Descoberto	SP	59333548	f	2026-06-10 13:39:56.262
cmq848iqu00dulz65qrzv6w7k	user_077	Sr. Carlos Costa	Travessa Carvalho	8202	\N	Esther do Sul	CE	35949302	t	2026-06-10 13:39:56.263
cmq848iqv00dwlz6525p2xdal	user_077	Elisa Souza	Avenida Reis	9288	\N	Fábio de Nossa Senhora	GO	71092010	f	2026-06-10 13:39:56.263
cmq848iqv00dylz65u3xmx767	user_078	Fábio Pereira	Rodovia Melo	9888	\N	Moreira do Sul	AM	07304283	t	2026-06-10 13:39:56.264
cmq848iqw00e0lz65kcdirv99	user_079	Dra. Helena Carvalho	Avenida Silva	9053	\N	Talita do Descoberto	PR	23171610	t	2026-06-10 13:39:56.265
cmq848iqx00e2lz65bkvbd8hl	user_079	Sr. Danilo Moreira	Rodovia Rafaela	133	\N	Saraiva do Sul	MG	22335161	f	2026-06-10 13:39:56.266
cmq848iqy00e4lz65t2bonjad	user_079	Liz Reis	Alameda Isadora	4135	Apto 137	Albuquerque do Descoberto	BA	91719373	f	2026-06-10 13:39:56.266
cmq848iqy00e6lz65g47p98b3	user_080	Carla Souza	Marginal Franco	6356	Apto 75	Batista do Descoberto	RS	26663824	t	2026-06-10 13:39:56.267
cmq848iqz00e8lz65dkn0pyp1	user_080	Daniel Silva	Rua Barros	6098	Apto 194	Helena do Descoberto	MA	04139192	f	2026-06-10 13:39:56.267
cmq848ir000ealz650kkk941a	user_081	Tertuliano Moreira Jr.	Avenida Macedo	9520	\N	Costa de Nossa Senhora	RS	79439443	t	2026-06-10 13:39:56.268
cmq848ir100eclz65uvcplfsd	user_081	Ladislau Saraiva	Rodovia Mércia	9409	\N	Martins do Descoberto	PE	64736175	f	2026-06-10 13:39:56.269
cmq848ir200eelz65fif9uko5	user_082	Meire Carvalho	Rodovia Silva	5250	\N	Beatriz do Descoberto	SP	09268517	t	2026-06-10 13:39:56.27
cmq848ir300eglz65ly1t8dii	user_083	Pedro Henrique Nogueira	Rua Franco	8157	\N	Rafaela de Nossa Senhora	MA	07814175	t	2026-06-10 13:39:56.271
cmq848ir300eilz65bkwrmt71	user_083	Davi Albuquerque	Rodovia Xavier	7192	\N	Reis do Descoberto	PR	55613697	f	2026-06-10 13:39:56.272
cmq848ir400eklz65lh2u5xiv	user_084	Lorenzo Pereira	Travessa Moraes	1976	\N	Karla do Norte	PE	25399537	t	2026-06-10 13:39:56.273
cmq848ir500emlz653uwg8vbo	user_084	Sra. Laura Souza	Travessa Moraes	6142	Apto 242	Antonella do Sul	RS	15705100	f	2026-06-10 13:39:56.273
cmq848ir500eolz65jd14itbg	user_084	Caio Melo	Travessa Lara	5776	\N	Antonella de Nossa Senhora	RJ	79986726	f	2026-06-10 13:39:56.274
cmq848ir600eqlz65atp22ja1	user_085	Melissa Franco	Travessa Lucas	5464	Apto 172	Batista do Descoberto	ES	36069515	t	2026-06-10 13:39:56.274
cmq848ir600eslz65koyy3qkv	user_085	Gustavo Oliveira	Rua Souza	7604	\N	Melissa de Nossa Senhora	RS	60341921	f	2026-06-10 13:39:56.275
cmq848ir700eulz65wxpq60jk	user_086	Dr. Heitor Albuquerque	Rodovia Souza	3880	\N	Pedro do Sul	SC	39237792	t	2026-06-10 13:39:56.275
cmq848ir700ewlz65wiulo49g	user_087	Benjamin Costa	Alameda Macedo	8018	\N	Carvalho de Nossa Senhora	PA	36472024	t	2026-06-10 13:39:56.276
cmq848ir800eylz6520pvdwtz	user_087	Isabella Barros	Rua Martins	7011	\N	Oliveira do Descoberto	BA	94597578	f	2026-06-10 13:39:56.276
cmq848ir900f0lz659z2z527a	user_088	Srta. Isis Pereira	Rua Gúbio	8777	Apto 414	Moraes de Nossa Senhora	CE	83112742	t	2026-06-10 13:39:56.277
cmq848ir900f2lz65zvp3dy5e	user_088	Isabel Macedo	Avenida Hélio	7097	\N	Marina de Nossa Senhora	MG	00714640	f	2026-06-10 13:39:56.278
cmq848ira00f4lz65x7kqdz6h	user_089	Melissa Melo	Travessa Théo	3358	\N	Melo de Nossa Senhora	ES	15224905	t	2026-06-10 13:39:56.279
cmq848irb00f6lz65gb4qf73e	user_089	Cecília Moraes	Rua Valentina	9447	Apto 286	Souza do Descoberto	MG	95024679	f	2026-06-10 13:39:56.279
cmq848irc00f8lz651yfc4ozy	user_090	João Pedro Braga	Travessa Moreira	6950	\N	Santos do Descoberto	BA	34747538	t	2026-06-10 13:39:56.28
cmq848irc00falz65tpl2qj5z	user_091	Liz Albuquerque	Travessa Silva	1395	\N	Macedo do Descoberto	PE	38299238	t	2026-06-10 13:39:56.281
cmq848ird00fclz65m8unc85f	user_092	Isabel Pereira	Rua Macedo	3157	\N	Heloísa do Sul	PE	45926760	t	2026-06-10 13:39:56.281
cmq848ird00felz65cwmgme4i	user_092	Benjamin Reis	Rua Carvalho	1338	\N	Isabella do Norte	DF	12224723	f	2026-06-10 13:39:56.282
cmq848ire00fglz65h6cjjdbd	user_092	Vitória Santos	Avenida Liz	7777	\N	Franco do Descoberto	SC	04367382	f	2026-06-10 13:39:56.282
cmq848ire00filz65k1wxv163	user_093	Nataniel Carvalho	Rodovia Moreira	2747	\N	Théo do Norte	GO	50243153	t	2026-06-10 13:39:56.283
cmq848irf00fklz65n1vb7l6d	user_093	Larissa Souza	Rua Santos	1140	\N	Melo do Norte	SP	60425167	f	2026-06-10 13:39:56.284
cmq848irg00fmlz655xgalk50	user_094	Carla Moreira	Alameda Roberto	6260	Apto 57	Bruna de Nossa Senhora	BA	96871726	t	2026-06-10 13:39:56.284
cmq848irh00folz659k2oz3ur	user_095	Sr. Enzo Souza	Rodovia Barros	8218	\N	Xavier do Sul	PE	03874044	t	2026-06-10 13:39:56.285
cmq848iri00fqlz65irehwdd9	user_096	Feliciano Barros	Travessa Maria Júlia	6622	\N	Bruna do Norte	SP	58844068	t	2026-06-10 13:39:56.286
cmq848irj00fslz651esz2buf	user_096	Júlia Silva	Avenida Saraiva	7600	Apto 422	Lívia do Descoberto	PA	51110580	f	2026-06-10 13:39:56.288
cmq848irk00fulz65re4j9pub	user_096	Manuela Franco	Avenida Oliveira	5807	\N	Batista do Descoberto	SC	89611856	f	2026-06-10 13:39:56.288
cmq848irl00fwlz65d9mfxu8i	user_097	Salvador Reis	Alameda Talita	335	\N	Daniel do Descoberto	CE	92175916	t	2026-06-10 13:39:56.289
cmq848irl00fylz65nzmoj31e	user_097	Cecília Nogueira	Travessa Vitória	2923	Apto 178	Costa do Sul	RJ	69194963	f	2026-06-10 13:39:56.29
cmq848irm00g0lz650o7f7ni8	user_098	Ana Luiza Batista	Rua Carvalho	977	Apto 462	Moreira do Norte	SC	62048589	t	2026-06-10 13:39:56.291
cmq848irn00g2lz65z7idw3na	user_099	Murilo Xavier	Marginal Márcia	9102	Apto 316	Heloísa do Sul	ES	91872029	t	2026-06-10 13:39:56.291
cmq848irn00g4lz654loyrv5a	user_100	Emanuel Albuquerque	Rua Oliveira	4052	\N	Sarah de Nossa Senhora	AM	92269957	t	2026-06-10 13:39:56.292
cmq848iro00g6lz65irr8zwdh	user_100	Vitória Braga	Avenida Gael	884	Apto 491	Xavier do Sul	PR	00159484	f	2026-06-10 13:39:56.292
cmq848iro00g8lz65euxpxnjz	user_101	Dr. Daniel Oliveira	Rodovia Melo	7964	\N	Oliveira de Nossa Senhora	MG	00822735	t	2026-06-10 13:39:56.293
cmq848irp00galz653fo9gvi8	user_101	Talita Silva	Rua Nogueira	4554	\N	Marina de Nossa Senhora	SC	28522684	f	2026-06-10 13:39:56.293
cmq848irp00gclz65wkf9f9ol	user_102	Miguel Moraes	Travessa Moraes	5658	\N	Nogueira de Nossa Senhora	MG	42939565	t	2026-06-10 13:39:56.294
cmq848irq00gelz6507knje3a	user_103	Antonella Melo	Rua Suélen	7104	\N	Oliveira de Nossa Senhora	DF	19162776	t	2026-06-10 13:39:56.294
cmq848irr00gglz65bambe0h5	user_104	Benício Costa	Marginal Davi Lucca	2390	Apto 206	Roberta do Sul	BA	30681176	t	2026-06-10 13:39:56.295
cmq848irs00gilz656fb3xspr	user_104	Maria Alice Macedo	Travessa Santos	4839	\N	Saraiva do Sul	RS	88290155	f	2026-06-10 13:39:56.296
cmq848irs00gklz65b3ixtprx	user_105	Sra. Talita Braga	Alameda Moreira	4596	\N	João Lucas do Sul	CE	16186195	t	2026-06-10 13:39:56.297
cmq848irt00gmlz65kftrqc44	user_105	Maria Alice Santos	Alameda Batista	5469	\N	Rafaela do Sul	RJ	02817163	f	2026-06-10 13:39:56.297
cmq848irt00golz65x8cir6h6	user_106	Maria Cecília Pereira	Rodovia Calebe	4275	Apto 351	Saraiva do Sul	CE	95384448	t	2026-06-10 13:39:56.298
cmq848iru00gqlz65pvoomz5z	user_106	Gustavo Moraes	Marginal Isabela	1069	Apto 475	Larissa de Nossa Senhora	SP	35534932	f	2026-06-10 13:39:56.298
cmq848irv00gslz65em8zuqh1	user_107	Sra. Melissa Pereira	Travessa Reis	523	\N	Félix do Norte	PR	91140199	t	2026-06-10 13:39:56.299
cmq848irv00gulz6513prpt93	user_108	Júlio Pereira	Avenida Batista	40	\N	Franco do Descoberto	PR	37500149	t	2026-06-10 13:39:56.3
cmq848irw00gwlz6546jvwrgj	user_109	Isaac Batista	Avenida Oliveira	9461	\N	Braga do Descoberto	PA	71813232	t	2026-06-10 13:39:56.3
cmq848irw00gylz65ch5d9b4o	user_109	Joana Barros Jr.	Rua Moreira	5616	Apto 99	Davi Lucca do Descoberto	ES	08721166	f	2026-06-10 13:39:56.301
cmq848irx00h0lz65f3wokpwn	user_110	Nataniel Costa	Rua Gustavo	9200	\N	Emanuel de Nossa Senhora	PE	04143781	t	2026-06-10 13:39:56.301
cmq848iry00h2lz65k6a241z2	user_110	Isadora Santos	Travessa Maria Alice	1214	\N	Souza do Norte	MG	38668890	f	2026-06-10 13:39:56.302
cmq848is000h4lz65b3kdoa60	user_111	Pedro Braga	Rua Macedo	181	\N	Saraiva do Descoberto	RJ	81985903	t	2026-06-10 13:39:56.304
cmq848is200h6lz65gv12zxc2	user_111	Fábio Barros	Alameda Saraiva	1950	\N	Carvalho do Norte	MA	49413938	f	2026-06-10 13:39:56.306
cmq848is300h8lz656j1ridoa	user_112	Ana Laura Franco	Travessa Gael	4431	Apto 184	Moreira do Norte	PR	29756065	t	2026-06-10 13:39:56.307
cmq848is400halz65oxpzxpxe	user_112	Félix Carvalho	Travessa Alícia	7172	\N	Braga do Descoberto	PE	22668402	f	2026-06-10 13:39:56.308
cmq848is400hclz65hrfefuoj	user_112	Lorenzo Albuquerque	Alameda Yango	5405	\N	Melo do Descoberto	CE	45315863	f	2026-06-10 13:39:56.309
cmq848is500helz65vn5469ys	user_113	Davi Lucca Reis	Rodovia Albuquerque	2467	\N	Costa do Norte	RJ	47692434	t	2026-06-10 13:39:56.31
cmq848is600hglz65lsgo5r0g	user_113	Nataniel Carvalho	Rodovia Heloísa	5121	\N	Rafaela de Nossa Senhora	MG	43975940	f	2026-06-10 13:39:56.31
cmq848is700hilz65jzz1i4fv	user_113	Karla Souza	Alameda Warley	8816	\N	Batista do Descoberto	CE	20705594	f	2026-06-10 13:39:56.311
cmq848is800hklz65t95ljjda	user_114	Samuel Melo	Avenida Albuquerque	3473	Apto 344	Barros do Norte	RJ	97686979	t	2026-06-10 13:39:56.312
cmq848is900hmlz65j2ltrwxk	user_115	Lorraine Nogueira	Rua Souza	3836	\N	Martins do Descoberto	ES	13027204	t	2026-06-10 13:39:56.314
cmq848isb00holz657wjvybct	user_115	Ana Laura Santos	Marginal Saraiva	7991	\N	Norberto do Sul	MG	22710908	f	2026-06-10 13:39:56.315
cmq848isd00hqlz65roqjs0jr	user_116	Dr. Júlio César Souza	Marginal Hélio	6070	Apto 403	Barros do Norte	CE	14355077	t	2026-06-10 13:39:56.317
cmq848isf00hslz65bijzca0n	user_117	Melissa Costa	Alameda Isabella	6970	\N	Maitê do Descoberto	RJ	80792358	t	2026-06-10 13:39:56.32
cmq848ish00hulz653vhwrwhs	user_118	Bernardo Martins	Avenida Hugo	3017	Apto 428	Costa do Sul	DF	55385115	t	2026-06-10 13:39:56.322
cmq848isj00hwlz65ve3rpv71	user_118	Feliciano Santos	Rua Davi	3713	\N	Moraes do Norte	AM	18656416	f	2026-06-10 13:39:56.323
cmq848isl00hylz65tlyhbfp7	user_118	Marcos Souza	Travessa Rafael	4946	\N	Sara do Sul	SC	80831242	f	2026-06-10 13:39:56.325
cmq848isn00i0lz65u6jcy0k9	user_119	Giovanna Melo	Rodovia Reis	1520	Apto 173	Batista do Sul	GO	25562836	t	2026-06-10 13:39:56.327
cmq848isp00i2lz658hp8hs8i	user_120	Isabella Barros	Marginal Kléber	7409	\N	Fabiano do Norte	PA	33489569	t	2026-06-10 13:39:56.33
\.


--
-- Data for Name: AuditLog; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."AuditLog" (id, "userId", "tableName", action, payload, "createdAt") FROM stdin;
201	user_013	Coupon	DELETE	{"detail": "Nemo eum laboriosam sapiente cumque neque suscipit."}	2026-03-14 08:41:45.775
202	user_057	Coupon	DELETE	{"detail": "Fugiat nobis quo sapiente modi modi officiis."}	2026-04-26 17:21:08.146
203	\N	Product	UPDATE	{"detail": "Blanditiis quia explicabo aut."}	2026-03-30 17:53:20.344
204	user_013	Order	INSERT	{"detail": "Ad veniam temporibus deserunt expedita culpa tenetur neque asperiores repellendus."}	2026-03-22 21:42:54.019
205	user_078	Product	INSERT	{"detail": "Deleniti voluptas optio rem aut tempore tempore magni sapiente dolor."}	2026-02-25 23:20:13.615
206	user_073	User	UPDATE	{"detail": "Consequatur quod sint doloribus provident ipsa eaque accusamus quibusdam."}	2026-02-04 17:15:31.481
207	user_059	Review	DELETE	{"detail": "Pariatur eveniet ipsum repellendus expedita delectus excepturi veritatis perspiciatis fuga."}	2026-01-11 20:39:50.007
208	user_072	User	UPDATE	{"detail": "Hic nobis alias cumque."}	2026-04-20 13:27:54.6
209	user_045	ProductSize	UPDATE	{"detail": "Vel quia voluptatibus velit distinctio fugit minima reprehenderit ratione."}	2026-02-24 11:48:56.406
210	user_068	ProductSize	INSERT	{"detail": "Qui amet id nihil ducimus explicabo maxime natus aspernatur."}	2026-02-10 01:26:13.609
211	\N	ProductSize	INSERT	{"detail": "Velit totam quibusdam iure eum."}	2026-05-22 00:24:00.413
212	user_068	Order	UPDATE	{"detail": "Aliquid asperiores accusamus nobis deleniti quam qui."}	2026-01-28 02:09:46.373
213	user_055	Review	INSERT	{"detail": "Deserunt totam officiis asperiores dicta explicabo explicabo."}	2026-04-09 10:10:03.209
214	user_088	User	UPDATE	{"detail": "Corrupti atque et ea corrupti quam necessitatibus saepe possimus."}	2026-02-10 07:21:33.205
215	user_048	Order	UPDATE	{"detail": "Veniam esse a."}	2026-01-29 13:09:08.183
216	\N	Order	INSERT	{"detail": "Laborum aperiam dolor voluptate veniam expedita laudantium."}	2025-12-31 11:14:15.077
217	\N	Order	DELETE	{"detail": "Delectus ducimus natus veniam dolorum quam iure fugiat eaque."}	2026-05-17 13:44:55.216
218	\N	ProductSize	UPDATE	{"detail": "Asperiores vitae provident fuga earum."}	2026-04-28 05:43:40.605
219	user_015	User	INSERT	{"detail": "Nobis eligendi mollitia praesentium sed veniam aspernatur nam consequuntur rerum."}	2026-04-11 12:41:04.476
220	user_017	Order	INSERT	{"detail": "Vitae assumenda optio qui distinctio est nobis ratione."}	2025-12-30 22:36:42.728
221	user_044	Coupon	DELETE	{"detail": "Ipsa aut rerum incidunt veniam corrupti architecto officia minima culpa."}	2026-05-08 11:04:17.485
222	user_112	ProductSize	DELETE	{"detail": "Omnis ex impedit omnis."}	2026-03-04 22:59:25.741
223	\N	User	INSERT	{"detail": "Error iure odio sapiente tempore vitae dolorem."}	2026-06-04 08:37:46.031
224	user_110	Order	DELETE	{"detail": "Dolore quos similique iusto assumenda repellendus illum maxime."}	2026-03-03 17:39:38.362
225	user_100	User	INSERT	{"detail": "Odit harum quis eius sapiente quo quisquam."}	2026-03-29 12:10:19.848
226	\N	Coupon	UPDATE	{"detail": "Ratione hic ex voluptatum sunt atque iste repellat voluptatibus delectus."}	2026-02-05 04:38:58.394
227	\N	User	DELETE	{"detail": "Praesentium delectus tenetur fuga."}	2026-05-01 14:01:59.919
228	user_087	ProductSize	INSERT	{"detail": "Beatae nam odit."}	2026-02-27 20:51:32.963
229	user_067	Coupon	DELETE	{"detail": "Quam aliquid nulla veniam eius soluta corporis."}	2026-05-10 22:18:49.014
230	user_085	Product	UPDATE	{"detail": "Facere reiciendis esse assumenda rerum."}	2026-06-02 19:16:48.374
231	\N	Product	DELETE	{"detail": "Aut non repudiandae recusandae quod maiores maxime."}	2025-12-02 22:31:51.938
232	user_004	Product	INSERT	{"detail": "Illum nulla natus recusandae blanditiis officiis voluptate."}	2026-01-22 16:08:45.722
233	\N	User	UPDATE	{"detail": "Id repellat sit necessitatibus alias."}	2026-02-08 04:52:44.897
234	user_091	Product	UPDATE	{"detail": "Aspernatur impedit ipsum dolor incidunt."}	2026-03-22 11:39:23.195
235	user_003	Order	UPDATE	{"detail": "Accusamus quisquam error quis rerum."}	2026-05-10 06:59:21.619
236	user_095	Coupon	UPDATE	{"detail": "Soluta neque quo maxime possimus."}	2026-02-28 20:29:48.58
237	user_012	Coupon	DELETE	{"detail": "Fugit earum asperiores eum perspiciatis quo cum reiciendis."}	2025-12-22 19:52:00.823
238	user_084	Review	DELETE	{"detail": "Laudantium repellendus vel autem numquam facere doloribus numquam ipsa facere."}	2026-03-28 20:14:56.543
239	\N	Order	INSERT	{"detail": "Veritatis eius sunt dolor beatae a."}	2026-01-22 22:14:45.504
240	user_108	Coupon	UPDATE	{"detail": "Assumenda vero officia officiis deleniti incidunt accusamus atque."}	2026-05-22 03:59:14.638
241	user_048	Review	INSERT	{"detail": "A accusamus molestias deserunt at quo similique maiores fuga voluptatibus."}	2025-12-11 21:41:29.199
242	user_055	User	DELETE	{"detail": "Voluptatibus enim eum incidunt."}	2026-03-21 01:53:53.142
243	user_018	Coupon	INSERT	{"detail": "Minus et iure sit."}	2026-02-04 21:26:30.267
244	user_011	Review	DELETE	{"detail": "Asperiores magnam veritatis."}	2025-12-01 23:06:21.751
306	user_028	Order	DELETE	{"detail": "Iusto harum a vitae repellendus cupiditate fugit."}	2026-01-26 11:00:03.215
245	user_076	Order	DELETE	{"detail": "Exercitationem tempore hic et aliquam quam ducimus atque."}	2026-01-27 02:51:31.298
246	user_078	ProductSize	INSERT	{"detail": "Ullam dignissimos repudiandae iusto aut iure."}	2026-05-05 22:09:20.524
247	user_062	Order	UPDATE	{"detail": "Repellat deserunt quidem dignissimos ullam placeat ducimus."}	2026-06-07 23:47:13.174
248	user_009	Coupon	INSERT	{"detail": "Ullam cum dignissimos voluptatem natus."}	2026-02-17 04:08:57.274
249	\N	User	DELETE	{"detail": "Optio nam saepe accusantium."}	2026-02-24 00:36:11.452
250	user_012	User	DELETE	{"detail": "Doloribus ipsa distinctio occaecati blanditiis reiciendis."}	2025-12-25 15:12:20.974
251	\N	Coupon	INSERT	{"detail": "Eum facere laboriosam illum culpa odit mollitia ratione ea magni."}	2025-12-05 04:23:36.554
252	user_065	User	UPDATE	{"detail": "Fuga facilis corporis accusamus."}	2026-04-02 08:44:45.124
253	user_034	Product	DELETE	{"detail": "Sunt voluptas id mollitia nulla odit eum quasi laboriosam."}	2025-12-03 20:53:23.826
254	\N	ProductSize	DELETE	{"detail": "Amet eius laboriosam."}	2026-05-02 13:04:14.37
255	user_025	Product	INSERT	{"detail": "Reprehenderit libero fuga aspernatur fugit eligendi nam voluptas inventore."}	2025-12-03 07:10:01.124
256	user_002	Order	UPDATE	{"detail": "Architecto necessitatibus cupiditate."}	2026-05-27 13:07:04.554
257	user_082	Order	UPDATE	{"detail": "Alias itaque quos recusandae."}	2026-02-02 10:16:18.293
258	user_049	Coupon	UPDATE	{"detail": "Sit facilis veniam eos praesentium blanditiis aspernatur nesciunt ea ea."}	2026-01-30 08:03:54.42
259	user_001	Review	DELETE	{"detail": "Repellat laborum ab dicta voluptates similique."}	2026-05-10 04:55:02.416
260	\N	User	INSERT	{"detail": "Ab ratione ea dicta."}	2026-01-01 16:18:12.996
261	user_041	User	UPDATE	{"detail": "Earum beatae architecto fugiat praesentium cumque ipsum assumenda."}	2026-05-25 12:44:26.183
262	user_013	Review	DELETE	{"detail": "Accusantium quod odit dolor occaecati modi id omnis beatae."}	2026-04-04 15:25:35.339
263	\N	Product	UPDATE	{"detail": "Esse labore ullam voluptatem maiores."}	2026-03-29 17:05:15.521
264	user_047	ProductSize	UPDATE	{"detail": "Quam incidunt eos quas quibusdam."}	2025-12-30 00:53:47.365
265	user_030	Review	DELETE	{"detail": "Itaque in maiores dolore adipisci officia voluptas."}	2026-03-30 00:13:36.737
266	user_075	Order	INSERT	{"detail": "Accusamus reiciendis distinctio fuga quas sunt ratione labore debitis dolores."}	2026-05-25 08:18:06.033
267	user_086	Product	INSERT	{"detail": "Modi dolore sequi explicabo consectetur officia voluptate quos sunt quod."}	2026-04-28 23:28:18.605
268	user_047	Product	DELETE	{"detail": "Saepe adipisci esse qui ipsam rem eaque distinctio."}	2026-03-14 05:25:03.804
269	\N	Order	DELETE	{"detail": "Repudiandae quo placeat sint ratione dolorum expedita doloribus atque tempora."}	2026-04-09 21:32:48.117
270	\N	Order	INSERT	{"detail": "Magni sit quis pariatur doloremque eum optio."}	2026-05-31 02:30:45.511
271	\N	User	DELETE	{"detail": "Soluta officia non."}	2026-03-07 09:22:20.507
272	user_105	User	UPDATE	{"detail": "Neque asperiores eligendi delectus."}	2026-01-26 05:04:52.728
273	user_061	User	INSERT	{"detail": "Corporis qui veniam molestias libero iusto rem odit."}	2026-05-23 18:59:26.22
274	\N	Coupon	INSERT	{"detail": "Similique repellat repellat nulla quae a iste."}	2026-05-02 04:02:37.224
275	user_039	User	INSERT	{"detail": "Nulla accusantium sed sunt ex."}	2026-06-08 10:15:36.966
276	user_018	Review	DELETE	{"detail": "Nobis animi cumque."}	2026-03-04 22:55:52.298
277	\N	Product	INSERT	{"detail": "In repudiandae quas aperiam ea commodi."}	2026-06-02 10:38:19.246
278	user_077	Coupon	DELETE	{"detail": "Adipisci vero tempore soluta repellat maxime assumenda a."}	2025-12-29 17:10:15.741
279	user_070	Order	DELETE	{"detail": "Nam repellat eius tempore quos quaerat consequuntur necessitatibus perspiciatis."}	2026-05-06 17:41:53.879
280	user_027	User	UPDATE	{"detail": "Consequatur doloribus maiores repellat molestiae delectus nisi sit dolor tenetur."}	2025-12-03 14:46:01.205
281	user_010	Order	INSERT	{"detail": "Provident saepe harum reiciendis praesentium officia sint odio quibusdam."}	2026-04-02 11:02:04.627
282	\N	Coupon	INSERT	{"detail": "Nesciunt cupiditate dolorum repellat voluptatem et inventore aliquid."}	2026-05-06 02:26:34.542
283	\N	Coupon	DELETE	{"detail": "Et ipsa fugiat libero rerum."}	2026-02-03 12:55:26.773
284	user_115	Product	DELETE	{"detail": "Doloremque soluta veniam nam facilis."}	2026-03-12 14:37:41.347
285	user_070	Order	DELETE	{"detail": "Aut saepe corrupti at accusamus reprehenderit praesentium."}	2026-02-17 23:50:24.028
286	user_108	Coupon	INSERT	{"detail": "Repellat perspiciatis quisquam cumque exercitationem ipsam nam."}	2026-03-05 23:55:29.655
287	user_086	Coupon	INSERT	{"detail": "Dolore praesentium nostrum excepturi."}	2025-12-11 03:48:13.327
288	user_045	ProductSize	UPDATE	{"detail": "Saepe qui fuga recusandae atque."}	2026-05-16 12:25:21.749
289	user_060	User	INSERT	{"detail": "Ipsam est earum veritatis minima reprehenderit."}	2026-02-25 11:38:43.166
290	user_054	Product	DELETE	{"detail": "Laudantium occaecati consequuntur dolor consectetur eum recusandae totam ratione modi."}	2026-02-11 23:06:30.728
291	user_053	User	UPDATE	{"detail": "Inventore sit non et."}	2026-02-02 21:42:47.922
292	user_086	ProductSize	DELETE	{"detail": "Officiis aliquid aliquid ex quasi."}	2026-06-04 08:14:12.021
293	user_041	Order	INSERT	{"detail": "Aperiam dolore pariatur quis."}	2025-12-24 12:02:05.115
294	user_120	Order	INSERT	{"detail": "Eos laudantium adipisci itaque maiores facere enim ex velit debitis."}	2026-05-23 18:23:08.687
295	user_079	Product	UPDATE	{"detail": "Laboriosam corporis alias maxime officiis reiciendis distinctio corrupti."}	2026-01-21 03:56:14.677
296	\N	ProductSize	DELETE	{"detail": "Quibusdam consequatur dolor est debitis fuga commodi corporis."}	2026-04-20 05:02:34.504
297	user_073	Order	DELETE	{"detail": "Quisquam ipsum nostrum vero eaque laudantium iusto."}	2026-04-22 17:36:34.781
298	user_027	Review	UPDATE	{"detail": "Sequi repellat sequi."}	2026-03-26 23:46:05.994
299	user_107	Coupon	UPDATE	{"detail": "Accusamus reprehenderit itaque."}	2026-03-05 03:39:28.435
300	user_009	Coupon	UPDATE	{"detail": "Dicta fugit qui minima debitis."}	2026-02-08 23:16:00.071
301	user_010	ProductSize	UPDATE	{"detail": "Illum voluptate quo sequi molestias illo exercitationem amet distinctio dignissimos."}	2026-04-22 16:52:52.981
302	user_011	Coupon	DELETE	{"detail": "Sint eligendi nobis quia consequuntur ab ad molestiae repellat eum."}	2026-04-17 23:39:58.333
303	user_025	Product	UPDATE	{"detail": "Repellat corporis necessitatibus suscipit harum perspiciatis eaque inventore."}	2025-12-04 22:41:03.296
304	user_090	Order	UPDATE	{"detail": "Quod quod quo rem ut."}	2026-05-03 19:03:53.425
305	user_035	Order	DELETE	{"detail": "Mollitia commodi architecto eveniet praesentium ea provident sequi."}	2025-12-26 04:25:20.757
307	user_083	Order	UPDATE	{"detail": "In pariatur at nihil voluptatibus illo alias suscipit."}	2026-03-25 05:00:09.36
308	user_058	Product	INSERT	{"detail": "Pariatur laborum id perspiciatis nesciunt vel quidem deleniti perferendis."}	2026-05-31 04:13:08.54
309	\N	Order	UPDATE	{"detail": "Quasi blanditiis esse ea temporibus suscipit quae quae doloremque ea."}	2026-04-16 11:55:57.455
310	user_078	Coupon	INSERT	{"detail": "Fuga quam quis natus voluptatibus vel nisi."}	2026-02-27 05:03:25.47
311	user_067	Order	INSERT	{"detail": "Alias ex beatae sit assumenda voluptates."}	2026-01-09 10:59:47.027
312	user_034	User	UPDATE	{"detail": "Rerum explicabo eaque cumque est."}	2026-03-05 17:16:44.854
313	user_060	User	UPDATE	{"detail": "Voluptatum harum expedita voluptas commodi voluptas."}	2026-03-12 22:36:11.26
314	user_107	Coupon	DELETE	{"detail": "Reiciendis culpa delectus quia eaque occaecati maiores autem."}	2026-01-10 06:55:03.833
315	user_078	Order	DELETE	{"detail": "Necessitatibus dolore minima ipsam nisi architecto optio nemo accusamus recusandae."}	2025-12-05 15:24:24.373
316	\N	Coupon	UPDATE	{"detail": "Totam minima error et error incidunt."}	2025-12-04 08:24:53.353
317	user_070	User	INSERT	{"detail": "Iste dicta praesentium ducimus ipsa omnis placeat nobis nesciunt nulla."}	2026-02-04 01:59:32.191
318	\N	Product	UPDATE	{"detail": "Non impedit similique perferendis omnis dignissimos sequi."}	2026-06-08 04:36:42.896
319	\N	Order	UPDATE	{"detail": "Quo itaque corporis maxime ducimus."}	2026-02-14 08:23:53.662
320	\N	ProductSize	UPDATE	{"detail": "Eius minima itaque dolorum assumenda tempora atque reiciendis."}	2026-01-30 13:17:23.206
321	user_062	User	INSERT	{"detail": "Asperiores excepturi impedit nulla rerum aperiam quia ab consequatur aliquam."}	2026-02-13 13:08:35.447
322	user_008	ProductSize	INSERT	{"detail": "Consequatur quibusdam a distinctio tempore itaque dolorem repellat impedit."}	2026-04-18 01:09:44.748
323	user_066	ProductSize	UPDATE	{"detail": "Inventore ullam eum eius dolores odit nemo dignissimos."}	2025-12-12 23:10:21.241
324	\N	Coupon	DELETE	{"detail": "Unde voluptatum maiores nobis."}	2026-03-20 09:28:27.083
325	\N	Product	INSERT	{"detail": "Quasi dicta soluta tempora similique voluptates enim ipsum."}	2025-12-21 05:55:36.299
326	user_008	Product	UPDATE	{"detail": "Facilis at porro voluptatum architecto."}	2026-04-14 20:32:19.733
327	user_011	Review	UPDATE	{"detail": "At saepe quis ullam."}	2026-03-21 03:06:21.909
328	user_008	ProductSize	DELETE	{"detail": "Eveniet tenetur modi eligendi adipisci."}	2026-04-20 03:30:24.831
329	user_030	Coupon	DELETE	{"detail": "Magni et sint maiores possimus."}	2026-02-21 19:25:43.513
330	user_034	Product	UPDATE	{"detail": "Totam a unde omnis explicabo repellat."}	2026-04-26 20:10:22.605
331	\N	User	UPDATE	{"detail": "Sequi harum saepe consequuntur veritatis cum tempora."}	2026-03-29 12:48:47.483
332	user_039	Coupon	UPDATE	{"detail": "Optio at perferendis velit et reprehenderit officiis nihil illum."}	2026-02-01 03:55:57.955
333	user_108	User	DELETE	{"detail": "Tenetur sint optio et."}	2026-03-04 14:32:55.931
334	\N	Review	INSERT	{"detail": "Reprehenderit dolores libero qui exercitationem."}	2026-04-06 00:33:34.935
335	user_089	Review	INSERT	{"detail": "Amet commodi voluptatem aspernatur ad nostrum necessitatibus soluta."}	2026-06-03 17:09:15.606
336	user_030	Order	INSERT	{"detail": "Laborum voluptatum laboriosam sed sit."}	2026-01-11 13:53:10.067
337	user_095	Product	DELETE	{"detail": "Illo placeat occaecati consectetur debitis aperiam."}	2026-01-08 08:17:50.688
338	user_086	Order	INSERT	{"detail": "Enim sequi laudantium eveniet doloremque cumque sint vel soluta."}	2026-06-02 12:09:33.752
339	user_018	Review	DELETE	{"detail": "Sint soluta impedit repudiandae vel dolore."}	2026-04-01 12:52:08.604
340	user_072	User	INSERT	{"detail": "Harum quod dignissimos magni commodi quisquam."}	2026-02-17 10:38:17.786
341	user_061	Order	DELETE	{"detail": "Rem dolorem ab."}	2026-03-06 13:22:43.511
342	user_085	Coupon	DELETE	{"detail": "Similique occaecati autem perspiciatis tenetur sequi."}	2026-05-22 02:19:14.725
343	user_038	Order	UPDATE	{"detail": "Accusamus assumenda mollitia esse."}	2026-05-27 06:16:46.388
344	\N	User	DELETE	{"detail": "Provident veniam quam inventore corporis quidem a."}	2026-06-01 23:34:20.476
345	user_073	Order	DELETE	{"detail": "Ut est quaerat."}	2025-12-10 11:18:06.285
346	\N	Order	INSERT	{"detail": "Non eos impedit."}	2026-01-31 02:52:45.31
347	\N	Order	UPDATE	{"detail": "Mollitia unde recusandae amet dignissimos accusamus inventore ipsa."}	2026-01-14 07:51:30.352
348	user_032	Order	UPDATE	{"detail": "Non magnam iste tenetur laborum porro nemo."}	2026-01-21 17:28:47.563
349	user_097	User	DELETE	{"detail": "Illo aperiam sed suscipit explicabo at sit enim qui itaque."}	2026-04-07 04:50:00.176
350	\N	Review	UPDATE	{"detail": "Sequi dolor facilis doloremque."}	2025-12-10 18:12:23.374
351	user_078	ProductSize	UPDATE	{"detail": "Deleniti beatae quod a ipsa nisi odio fugit pariatur."}	2026-01-23 23:43:20.57
352	user_081	ProductSize	INSERT	{"detail": "Aperiam adipisci nostrum repellendus."}	2026-02-08 14:45:02.017
353	user_053	Coupon	DELETE	{"detail": "Nulla error facere mollitia."}	2026-02-19 13:12:35.111
354	user_009	ProductSize	DELETE	{"detail": "Minima assumenda cumque ut aut dicta vero temporibus."}	2026-01-26 02:09:10.958
355	user_096	Review	DELETE	{"detail": "Velit rem consectetur placeat laboriosam repellendus suscipit."}	2026-05-06 14:07:16.636
356	user_053	ProductSize	INSERT	{"detail": "Sint praesentium temporibus pariatur rem recusandae quae vitae perspiciatis ullam."}	2026-02-27 04:52:00.328
357	user_049	Coupon	UPDATE	{"detail": "Quisquam tempora modi quis quibusdam sit amet saepe officia amet."}	2026-01-11 15:18:03.798
358	\N	Review	INSERT	{"detail": "Repellendus impedit facere totam eveniet minima."}	2025-12-30 18:25:29.757
359	user_065	Review	INSERT	{"detail": "Dolore animi doloremque omnis distinctio ipsam ipsum deleniti repellendus."}	2026-01-31 11:22:33.434
360	user_034	Review	UPDATE	{"detail": "Porro rerum explicabo."}	2026-06-06 03:09:48.154
361	user_061	User	DELETE	{"detail": "Labore sunt optio perspiciatis."}	2026-03-26 17:20:30.235
362	user_079	Coupon	UPDATE	{"detail": "Exercitationem eligendi accusantium quos reiciendis maiores ut reprehenderit quae."}	2026-05-15 22:26:10.906
363	user_047	Product	DELETE	{"detail": "Ut exercitationem tempora unde itaque fugiat esse."}	2026-05-07 00:50:13.532
364	user_031	Review	INSERT	{"detail": "Asperiores aspernatur optio earum laudantium."}	2025-12-01 11:29:57.24
365	user_014	User	DELETE	{"detail": "Eum quas occaecati fugiat quaerat possimus."}	2026-03-18 12:39:28.419
366	user_036	User	UPDATE	{"detail": "Repudiandae sint repudiandae aperiam."}	2026-02-04 02:18:28.257
367	user_033	Review	INSERT	{"detail": "Dicta commodi temporibus error cum exercitationem."}	2026-05-29 10:27:12.562
368	user_051	User	DELETE	{"detail": "Facilis commodi dolor nam omnis blanditiis error."}	2026-01-09 13:46:56.181
369	user_114	Review	INSERT	{"detail": "Placeat perspiciatis corrupti recusandae deleniti laudantium."}	2025-12-08 23:36:17.194
370	user_001	Review	UPDATE	{"detail": "Quibusdam omnis omnis dolore repellendus magni."}	2025-12-11 02:21:43.705
371	user_033	Order	DELETE	{"detail": "Dolorum et fugit praesentium."}	2026-05-25 03:50:41.496
372	\N	Review	UPDATE	{"detail": "Error error fugit atque laboriosam reprehenderit rem explicabo."}	2026-02-07 07:15:50.639
373	user_118	Product	INSERT	{"detail": "Iusto aspernatur suscipit dicta nesciunt eaque iure maxime cupiditate omnis."}	2026-01-08 02:39:47.438
374	user_102	Product	DELETE	{"detail": "Temporibus enim quis nobis porro amet."}	2026-06-03 20:17:35.669
375	user_009	ProductSize	DELETE	{"detail": "Ex sit unde labore eum odio quae odio vel expedita."}	2026-04-02 16:14:11.599
376	user_025	Order	INSERT	{"detail": "Asperiores mollitia omnis ea quaerat eveniet reiciendis ducimus."}	2026-01-25 03:18:51.334
377	user_016	Coupon	DELETE	{"detail": "Voluptatibus doloribus earum."}	2026-03-05 05:55:07.431
378	user_070	User	INSERT	{"detail": "Id ab veniam perferendis nobis officia."}	2025-12-12 21:47:05.763
379	\N	Product	UPDATE	{"detail": "Quisquam accusantium saepe repudiandae molestias iusto aperiam molestias ea."}	2026-04-26 19:59:49.984
380	user_083	Product	INSERT	{"detail": "Aperiam atque minus iste."}	2026-03-20 05:47:39.401
381	user_041	User	INSERT	{"detail": "Consequuntur aut perspiciatis hic omnis porro laborum ducimus."}	2026-04-16 11:52:09.668
382	\N	Order	UPDATE	{"detail": "Voluptate officiis nostrum voluptas."}	2026-05-13 11:16:28.525
383	user_065	Review	UPDATE	{"detail": "Veritatis eos ex ducimus delectus reiciendis illum enim."}	2026-06-02 03:58:08.423
384	user_048	Coupon	INSERT	{"detail": "Repellendus deserunt nemo blanditiis."}	2026-05-21 23:26:53.529
385	user_048	Product	INSERT	{"detail": "Iure nihil ducimus accusamus unde quidem laboriosam voluptatem itaque tenetur."}	2026-05-30 08:08:16.524
386	\N	Coupon	DELETE	{"detail": "Unde aspernatur nisi reiciendis exercitationem pariatur et veniam exercitationem."}	2025-12-10 19:18:27.347
387	user_024	Review	INSERT	{"detail": "Consequatur quidem natus deserunt voluptas."}	2026-01-09 13:42:04.554
388	user_098	Product	UPDATE	{"detail": "Magni tempore deleniti ipsum."}	2026-01-28 21:36:00.184
389	\N	Review	DELETE	{"detail": "Error voluptas inventore aliquid perspiciatis labore."}	2026-05-11 02:39:16.635
390	user_045	Product	UPDATE	{"detail": "Tempora aliquid iusto."}	2026-03-14 07:15:19.421
391	user_063	ProductSize	INSERT	{"detail": "Corrupti veniam tenetur quibusdam maiores harum voluptas ut id."}	2026-06-05 08:31:25.019
392	user_106	Order	UPDATE	{"detail": "Eligendi maiores quo in voluptatum necessitatibus quos numquam iure laudantium."}	2025-12-19 09:02:32.787
393	user_014	User	DELETE	{"detail": "Quibusdam nostrum sapiente dolorem accusantium at."}	2026-04-22 22:02:39.785
394	user_119	ProductSize	DELETE	{"detail": "Nihil in veniam deleniti voluptate accusantium eius."}	2026-01-10 11:50:23.886
395	\N	ProductSize	DELETE	{"detail": "Deserunt maiores quaerat qui ex nihil debitis quas dolore soluta."}	2026-03-07 02:35:37.08
396	user_070	Review	DELETE	{"detail": "Voluptas veritatis nihil nobis corporis consectetur itaque."}	2026-05-06 02:17:38.379
397	user_017	Product	INSERT	{"detail": "Dicta quibusdam asperiores nemo voluptate expedita earum."}	2026-05-19 21:04:03.387
398	user_021	Coupon	DELETE	{"detail": "Blanditiis porro ipsum at."}	2025-12-11 01:33:04.655
399	user_074	Order	DELETE	{"detail": "Itaque nemo fuga unde rem debitis alias ut deleniti."}	2026-01-03 21:01:02.183
400	\N	ProductSize	UPDATE	{"detail": "Voluptate quas alias nemo odit harum iusto magnam nihil."}	2026-01-09 19:54:44.24
\.


--
-- Data for Name: Brand; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Brand" (id, name, "logoUrl", "createdAt") FROM stdin;
cmq848igo0006lz65r9knigm5	Nike	/brands/nike.png	2026-06-10 13:39:55.897
cmq848igp0007lz65zh407rd4	Adidas	/brands/adidas.png	2026-06-10 13:39:55.898
cmq848igq0008lz657r4exker	Puma	/brands/puma.png	2026-06-10 13:39:55.898
cmq848igq0009lz655mjc9c85	Umbro	/brands/umbro.png	2026-06-10 13:39:55.899
cmq848igr000alz659fxugp0h	New Balance	/brands/new-balance.png	2026-06-10 13:39:55.899
\.


--
-- Data for Name: Category; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Category" (id, name, slug, "createdAt") FROM stdin;
cmq848igi0000lz650ssfolol	Times Brasileiros	times-brasileiros	2026-06-10 13:39:55.891
cmq848igk0001lz65ezdcc7ni	Times Europeus	times-europeus	2026-06-10 13:39:55.893
cmq848igl0002lz65rhw1hugd	Seleções	selecoes	2026-06-10 13:39:55.894
cmq848igm0003lz65gh61iz19	Retrô	retro	2026-06-10 13:39:55.895
cmq848ign0004lz65su0853p9	Edição Limitada	edicao-limitada	2026-06-10 13:39:55.895
cmq848igo0005lz65782pyu95	Infantil	infantil	2026-06-10 13:39:55.896
\.


--
-- Data for Name: Coupon; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Coupon" (id, code, type, value, "validUntil", active, "firstPurchaseOnly", "maxUsesPerCustomer", "maxUsesGlobal", "createdAt") FROM stdin;
cmq848isv00i3lz65g690cqbu	BEMVINDO10	percent	10	2026-09-08 13:39:56.331	t	f	\N	\N	2026-06-10 13:39:56.336
cmq848isy00i4lz65xavthqzc	FUTSTORE20	percent	20	2026-09-08 13:39:56.337	t	f	\N	\N	2026-06-10 13:39:56.338
cmq848isz00i5lz65zu1x56pv	FRETE15	percent	15	2026-09-08 13:39:56.338	t	f	\N	\N	2026-06-10 13:39:56.34
cmq848it100i6lz65yjwh5v1c	BLACK30	fixed	30	2026-09-08 13:39:56.34	t	f	\N	\N	2026-06-10 13:39:56.341
cmq848it200i7lz65mq7faj20	COPA2026	fixed	50	2026-09-08 13:39:56.342	t	f	\N	\N	2026-06-10 13:39:56.343
\.


--
-- Data for Name: Order; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Order" (id, "userId", "userEmail", "couponCode", subtotal, discount, shipping, total, status, "trackingCode", "paymentMethod", "paymentBrand", "paymentLast4", "paymentHolderName", "addressFullName", "addressStreet", "addressNumber", "addressComplement", "addressCity", "addressState", "addressZip", "statusHistory", "createdAt") FROM stdin;
cmq848it500i9lz65ikq63i80	user_012	user_012@email.com	\N	279.9	0	25	304.9	enviado	BR2708450309842	boleto	Mastercard	1590	Sílvia Batista	Sr. Isaac Pereira	Avenida Fabrício	865	Apto 90	Franco de Nossa Senhora	RS	11279928	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-02-22T04:17:00.731Z\\"}]"	2026-02-22 04:17:00.731
cmq848itc00iblz65livqt9c5	user_040	user_040@email.com	\N	299.9	0	25	324.9	pendente	\N	boleto	Visa	3453	Sirineu Santos	Roberto Martins	Avenida Feliciano	981	\N	Elisa de Nossa Senhora	PE	47743370	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-04-19T23:46:59.640Z\\"}]"	2026-04-19 23:46:59.64
cmq848itf00idlz65df7sbixf	user_002	user_002@email.com	FUTSTORE20	1399.6	139.96	25	1284.64	entregue	BR6490599136199	credit_card	Visa	0914	Margarida Carvalho	Pietro Franco	Rodovia Benício	9090	\N	Fabrício de Nossa Senhora	RS	15950638	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-07T11:25:35.607Z\\"}]"	2026-01-07 11:25:35.607
cmq848itl00iflz6595hhlyrj	user_053	user_053@email.com	\N	599.8	0	25	624.8	entregue	BR9923154993488	credit_card	Mastercard	4210	Enzo Carvalho	Joaquim Xavier	Avenida Isadora	9108	\N	Arthur do Descoberto	PE	56046663	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-31T02:53:23.428Z\\"}]"	2026-01-31 02:53:23.428
cmq848itn00ihlz65x4aoy3ar	user_012	user_012@email.com	\N	1119.7	0	25	1144.7	entregue	BR0571280744083	pix	Elo	7953	Marcos Batista	Maria Eduarda Carvalho	Travessa Henrique	7486	\N	Moreira do Sul	SC	88344109	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-14T18:12:49.711Z\\"}]"	2026-05-14 18:12:49.711
cmq848itp00ijlz655ndot5yl	user_029	user_029@email.com	\N	389.9	0	25	414.9	entregue	BR0187335022282	credit_card	Elo	8203	Júlio César Xavier	João Xavier	Marginal Marcela	5868	Apto 168	Luiza do Norte	GO	73619370	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-04T16:01:40.693Z\\"}]"	2026-02-04 16:01:40.693
cmq848itr00illz65k87uxr4y	user_025	user_025@email.com	\N	1399.7	0	25	1424.7	pendente	\N	boleto	Elo	6716	Liz Braga	Maria Alice Moraes Neto	Alameda Santos	4328	Apto 130	Lucca de Nossa Senhora	MA	00961358	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-05-20T22:13:58.626Z\\"}]"	2026-05-20 22:13:58.626
cmq848itt00inlz65yoczfnn0	user_006	user_006@email.com	FUTSTORE20	459.9	45.99	25	438.91	pendente	\N	credit_card	Amex	4794	Srta. Lorena Santos	Vicente Moreira	Travessa Felícia	3245	\N	Maria Helena do Descoberto	SP	47866191	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2025-12-13T17:28:45.805Z\\"}]"	2025-12-13 17:28:45.805
cmq848itw00iplz65ztydciuv	user_093	user_093@email.com	\N	369.9	0	25	394.9	pendente	\N	credit_card	Amex	8285	Heloísa Reis	Nicolas Barros	Avenida Lavínia	8868	Apto 150	Yasmin do Sul	PA	25247729	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-03-28T09:13:41.402Z\\"}]"	2026-03-28 09:13:41.402
cmq848iu000irlz65o8902je4	user_072	user_072@email.com	\N	1379.7	0	25	1404.7	pago	\N	boleto	Amex	3151	Danilo Martins	Hélio Costa	Alameda Noah	9377	\N	Franco do Sul	PA	98194040	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2025-12-25T21:43:27.009Z\\"}]"	2025-12-25 21:43:27.009
cmq848iu200itlz65siyd733v	user_066	user_066@email.com	\N	939.6999999999999	0	25	964.6999999999999	entregue	BR0681889293500	boleto	Mastercard	2160	Benício Martins	Sra. Heloísa Oliveira	Avenida Nogueira	5703	Apto 29	Moreira de Nossa Senhora	PR	98701419	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-12T01:36:51.760Z\\"}]"	2026-03-12 01:36:51.76
cmq848iu400ivlz65fpjqwil8	user_020	user_020@email.com	\N	769.8	0	25	794.8	entregue	BR7095330906492	pix	Mastercard	7012	Danilo Carvalho	Dr. João Miguel Carvalho	Alameda Pereira	4893	\N	Laura do Norte	PR	93045179	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-08T06:27:11.779Z\\"}]"	2026-05-08 06:27:11.779
cmq848iu600ixlz6548rvqso5	user_114	user_114@email.com	\N	479.9	0	25	504.9	pendente	\N	pix	Elo	1966	Margarida Barros	Marcela Melo Filho	Marginal Xavier	2863	Apto 130	Júlio de Nossa Senhora	BA	01862065	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-03-02T05:24:55.169Z\\"}]"	2026-03-02 05:24:55.169
cmq848iu700izlz65ygufdo5l	user_049	user_049@email.com	\N	799.8	0	25	824.8	entregue	BR5310716344313	pix	Elo	2412	Sara Carvalho	Maria Cecília Batista	Marginal Emanuel	6508	Apto 108	Margarida do Sul	CE	96422439	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-06T18:36:54.119Z\\"}]"	2026-05-06 18:36:54.119
cmq848iu900j1lz65ncvvpnsz	user_045	user_045@email.com	\N	789.8	0	25	814.8	entregue	BR4608431444649	pix	Amex	1335	Benício Saraiva	Júlio Batista Neto	Travessa Souza	8369	\N	Maria do Sul	BA	22703557	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-08T10:08:22.355Z\\"}]"	2026-03-08 10:08:22.355
cmq848iuc00j3lz65bcrmx0k8	user_043	user_043@email.com	\N	679.8	0	25	704.8	pago	\N	boleto	Mastercard	4310	Ígor Albuquerque	Ofélia Souza	Travessa Braga	5079	\N	Batista do Norte	SC	58908035	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-05-09T16:25:08.193Z\\"}]"	2026-05-09 16:25:08.193
cmq848iug00j5lz65pe2jg1ub	user_018	user_018@email.com	FRETE15	1199.7	119.97	25	1104.73	entregue	BR5018781920926	credit_card	Elo	9361	Frederico Franco Filho	Emanuelly Franco	Travessa Braga	6906	\N	Silva do Sul	SC	46396036	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-18T07:33:51.028Z\\"}]"	2026-02-18 07:33:51.028
cmq848iui00j7lz655zhjnsmv	user_007	user_007@email.com	\N	459.9	0	25	484.9	entregue	BR2350108777646	credit_card	Elo	7532	Nataniel Macedo	Tertuliano Moraes	Rodovia Souza	5299	\N	Morgana do Norte	CE	33808259	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-04-10T22:29:37.348Z\\"}]"	2026-04-10 22:29:37.348
cmq848iuk00j9lz65oqqcvfyy	user_082	user_082@email.com	\N	1199.7	0	25	1224.7	pago	\N	boleto	Elo	8032	Ana Júlia Carvalho	Srta. Vitória Souza	Rua Souza	5424	\N	Natália do Descoberto	DF	69260617	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2025-12-06T21:37:09.677Z\\"}]"	2025-12-06 21:37:09.677
cmq848ium00jblz65hskdikov	user_037	user_037@email.com	BLACK30	669.8	66.98	25	627.8199999999999	pago	\N	credit_card	Amex	8160	Mariana Oliveira	Antonella Moraes	Avenida Aline	3411	\N	Albuquerque do Sul	PA	09439055	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-01-16T23:15:34.906Z\\"}]"	2026-01-16 23:15:34.906
cmq848iun00jdlz652knhe2s9	user_027	user_027@email.com	\N	809.8	0	25	834.8	pago	\N	credit_card	Visa	1782	Eloá Batista	Lorena Souza	Travessa Reis	4516	\N	Barros do Descoberto	ES	42814663	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2025-12-24T09:07:03.660Z\\"}]"	2025-12-24 09:07:03.66
cmq848iup00jflz658euo1qmh	user_105	user_105@email.com	FRETE15	1149.7	114.97	25	1059.73	entregue	BR7244421101063	boleto	Visa	3308	Sílvia Moreira	Dr. Guilherme Albuquerque	Rodovia Carvalho	3941	Apto 81	Raul de Nossa Senhora	SC	48742852	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-27T14:40:52.079Z\\"}]"	2026-01-27 14:40:52.079
cmq848iut00jhlz65tlix4m0l	user_033	user_033@email.com	\N	1159.7	0	25	1184.7	entregue	BR1146710928871	boleto	Amex	5321	Leonardo Melo	Vicente Martins Neto	Rodovia Barros	6030	Apto 179	Braga do Descoberto	SC	83145020	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-16T12:17:14.715Z\\"}]"	2026-01-16 12:17:14.715
cmq848iuy00jjlz65qon3bzh4	user_051	user_051@email.com	\N	1629.5	0	25	1654.5	cancelado	\N	boleto	Mastercard	7862	Heloísa Costa	Sarah Reis	Rodovia Gabriel	7565	Apto 139	Hugo do Norte	PA	26746484	"[{\\"status\\":\\"cancelado\\",\\"at\\":\\"2026-02-22T08:20:34.575Z\\"}]"	2026-02-22 08:20:34.575
cmq848iv300jllz654jv96sfh	user_102	user_102@email.com	FRETE15	1489.6	148.96	25	1365.64	entregue	BR8399207417081	credit_card	Visa	9683	Eloá Moreira	Sra. Sílvia Xavier	Travessa Henrique	4149	\N	Nogueira do Norte	PR	34312166	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-19T19:17:48.921Z\\"}]"	2025-12-19 19:17:48.921
cmq848iv600jnlz65mvzs49qd	user_115	user_115@email.com	\N	2139.5	0	25	2164.5	entregue	BR9308614774396	pix	Mastercard	7215	Maria Alice Oliveira	Bruna Silva	Alameda Pereira	636	Apto 193	Pereira do Norte	AM	39039325	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-22T02:29:27.766Z\\"}]"	2026-03-22 02:29:27.766
cmq848iv900jplz65cl1p86ui	user_099	user_099@email.com	\N	299.9	0	25	324.9	pendente	\N	boleto	Visa	4433	Maria Júlia Carvalho	Joaquim Oliveira	Marginal Ana Luiza	68	Apto 14	Costa do Sul	PA	53833233	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-02-15T10:27:49.435Z\\"}]"	2026-02-15 10:27:49.435
cmq848ive00jrlz65ed1xt7nq	user_082	user_082@email.com	BEMVINDO10	919.8	91.98	25	852.8199999999999	pago	\N	credit_card	Visa	3117	Maitê Moraes	Giovanna Silva Jr.	Travessa Batista	5893	\N	Mércia do Norte	RS	05776176	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-04-06T04:10:40.774Z\\"}]"	2026-04-06 04:10:40.774
cmq848ivh00jtlz65z8gk6d9q	user_003	user_003@email.com	\N	1419.6	0	25	1444.6	entregue	BR4829670170806	pix	Elo	6310	João Miguel Moraes	Aline Xavier	Alameda Henrique	180	Apto 103	Braga do Sul	GO	86608727	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-03T00:39:20.804Z\\"}]"	2025-12-03 00:39:20.804
cmq848ivl00jvlz65tdudivac	user_026	user_026@email.com	FUTSTORE20	459.9	45.99	25	438.91	entregue	BR6328784162408	credit_card	Amex	8476	Heitor Melo	Larissa Saraiva	Travessa Pedro	8111	Apto 94	Saraiva do Norte	SP	13250181	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-21T10:16:34.331Z\\"}]"	2026-01-21 10:16:34.331
cmq848ivn00jxlz65rw5hjmft	user_029	user_029@email.com	\N	829.8	0	25	854.8	pago	\N	pix	Mastercard	1254	Daniel Saraiva	Sra. Vitória Nogueira	Rodovia Rafael	7041	\N	Yago de Nossa Senhora	PA	95542025	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-02-14T09:48:56.277Z\\"}]"	2026-02-14 09:48:56.277
cmq848ivr00jzlz652l5i52c3	user_046	user_046@email.com	\N	789.8	0	25	814.8	cancelado	\N	credit_card	Visa	0131	Feliciano Carvalho	Rafaela Costa	Alameda Fabrícia	2069	\N	Maria Júlia do Norte	DF	81761649	"[{\\"status\\":\\"cancelado\\",\\"at\\":\\"2025-12-29T11:22:27.706Z\\"}]"	2025-12-29 11:22:27.706
cmq848ivv00k1lz65z3okgg8h	user_017	user_017@email.com	\N	1499.6	0	25	1524.6	entregue	BR5202241870669	credit_card	Visa	9977	Lorena Braga	Larissa Braga	Alameda Martins	3093	Apto 195	Alessandro do Norte	PE	92167632	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-18T00:08:35.843Z\\"}]"	2026-01-18 00:08:35.843
cmq848ivy00k3lz653bpabtwa	user_115	user_115@email.com	\N	2169.5	0	25	2194.5	entregue	BR5318485686358	pix	Mastercard	0906	Janaína Barros	Roberto Silva	Travessa Silva	4482	Apto 79	Fabrícia do Sul	PA	06130278	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-16T20:08:13.175Z\\"}]"	2026-03-16 20:08:13.175
cmq848iw000k5lz65tmh7mejf	user_027	user_027@email.com	\N	829.8	0	25	854.8	entregue	BR5535647814462	pix	Amex	4991	Dra. Sílvia Batista	Sr. Daniel Saraiva	Rodovia Maria Júlia	6742	Apto 7	Natália do Sul	PA	46684225	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-22T09:01:43.834Z\\"}]"	2026-05-22 09:01:43.834
cmq848iw200k7lz659m1u0m3r	user_054	user_054@email.com	\N	619.8	0	25	644.8	entregue	BR2184404557128	boleto	Visa	4203	Srta. Mariana Braga	Maria Nogueira	Avenida Júlia	6583	Apto 3	Nogueira de Nossa Senhora	DF	59832257	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-24T07:02:14.838Z\\"}]"	2026-02-24 07:02:14.838
cmq848iw500k9lz65w52cxj6w	user_061	user_061@email.com	\N	319.9	0	25	344.9	enviado	BR5684372387423	credit_card	Visa	7243	Guilherme Barros	Gúbio Barros	Rua Batista	6097	Apto 51	Silas do Descoberto	AM	32406581	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-05-18T22:23:03.344Z\\"}]"	2026-05-18 22:23:03.344
cmq848iw900kblz65l26lo7su	user_097	user_097@email.com	\N	1539.5	0	25	1564.5	entregue	BR1836544706801	boleto	Mastercard	4151	Melissa Moraes	Dr. Samuel Santos	Travessa Fábio	6546	\N	Macedo do Descoberto	BA	91083633	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-04-26T20:18:18.540Z\\"}]"	2026-04-26 20:18:18.54
cmq848iwd00kdlz657i68mzlq	user_032	user_032@email.com	\N	919.8	0	25	944.8	entregue	BR8280796409406	pix	Visa	2056	Sr. Ricardo Nogueira	Maitê Macedo	Marginal Sophia	1125	Apto 67	Marcela de Nossa Senhora	DF	03867630	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-10T08:09:46.323Z\\"}]"	2025-12-10 08:09:46.323
cmq848iwf00kflz65cgzsxcve	user_033	user_033@email.com	\N	1669.5	0	25	1694.5	cancelado	\N	pix	Elo	6597	Sirineu Barros	Roberto Moreira	Alameda Cauã	5943	\N	Vitória de Nossa Senhora	GO	21666083	"[{\\"status\\":\\"cancelado\\",\\"at\\":\\"2026-04-23T12:47:38.266Z\\"}]"	2026-04-23 12:47:38.266
cmq848iwi00khlz652fjlgtnc	user_038	user_038@email.com	\N	1499.6	0	25	1524.6	entregue	BR8053368682540	pix	Elo	5750	Margarida Barros	Felipe Oliveira	Alameda Albuquerque	6965	Apto 189	Carvalho de Nossa Senhora	PR	42519199	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-20T14:56:01.408Z\\"}]"	2026-03-20 14:56:01.408
cmq848iwl00kjlz6509btyvv7	user_064	user_064@email.com	\N	1049.7	0	25	1074.7	entregue	BR1806284353519	pix	Mastercard	7384	Bryan Reis	Heloísa Costa	Travessa Washington	5167	\N	Nogueira do Sul	RJ	82229873	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-18T03:45:52.240Z\\"}]"	2026-01-18 03:45:52.24
cmq848iwp00kllz65v0uxycd4	user_061	user_061@email.com	\N	949.6999999999999	0	25	974.6999999999999	entregue	BR7772343731392	pix	Mastercard	0475	Fabiano Souza	Rafael Reis Jr.	Marginal Marina	9433	\N	Melo do Norte	PA	99884683	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-09T07:11:41.712Z\\"}]"	2026-02-09 07:11:41.712
cmq848iws00knlz65khwmvu79	user_116	user_116@email.com	\N	789.8	0	25	814.8	pago	\N	credit_card	Mastercard	6419	Pablo Macedo	Lívia Moraes Neto	Rua Lucas	6595	Apto 182	Xavier do Sul	GO	81222800	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-03-15T22:08:00.951Z\\"}]"	2026-03-15 22:08:00.951
cmq848iwv00kplz659us0k4lh	user_033	user_033@email.com	\N	449.9	0	25	474.9	entregue	BR6777098909880	boleto	Amex	6594	Isaac Barros	Rafael Souza	Travessa Isabel	5369	\N	Nogueira do Norte	RJ	28948374	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-16T11:57:18.959Z\\"}]"	2026-02-16 11:57:18.959
cmq848iwx00krlz65q020xvi2	user_015	user_015@email.com	\N	2229.5	0	25	2254.5	entregue	BR3062373217145	boleto	Elo	8022	Giovanna Moraes	Marina Franco	Rua Sílvia	7215	Apto 170	Martins do Descoberto	MG	55559988	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-24T13:12:33.416Z\\"}]"	2026-02-24 13:12:33.416
cmq848iwz00ktlz65zq87bmxq	user_114	user_114@email.com	\N	279.9	0	25	304.9	entregue	BR7132373508367	credit_card	Amex	6419	Davi Lucca Saraiva	Henrique Martins	Rodovia Pereira	5415	\N	Reis do Sul	RS	68138207	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-27T09:39:25.804Z\\"}]"	2025-12-27 09:39:25.804
cmq848ix200kvlz651uwqfyjz	user_101	user_101@email.com	\N	919.8	0	25	944.8	pendente	\N	pix	Elo	8757	Ana Clara Barros	Dr. Gúbio Franco	Travessa Souza	2660	Apto 110	Reis de Nossa Senhora	PR	00440625	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-01-06T20:36:44.785Z\\"}]"	2026-01-06 20:36:44.785
cmq848ix500kxlz65z0ufk33v	user_037	user_037@email.com	FRETE15	299.9	29.99	25	294.91	entregue	BR1405255955497	credit_card	Amex	4881	Fabiano Franco	Alessandra Braga Jr.	Travessa Valentina	7160	Apto 64	Carlos do Descoberto	PA	82386360	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-04-07T11:38:40.831Z\\"}]"	2026-04-07 11:38:40.831
cmq848ix900kzlz65ldrrbp41	user_089	user_089@email.com	\N	919.8	0	25	944.8	enviado	BR9898211268860	credit_card	Visa	3503	Maria Clara Moraes	Davi Lucca Reis	Travessa Nogueira	2882	Apto 109	Oliveira do Descoberto	RS	47533696	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-05-17T23:01:47.506Z\\"}]"	2026-05-17 23:01:47.506
cmq848ixa00l1lz65i43t0gar	user_009	user_009@email.com	COPA2026	1559.6	155.96	25	1428.64	pendente	\N	boleto	Visa	5133	Sra. Isabela Braga	Caio Reis	Marginal Pereira	5868	\N	João Pedro de Nossa Senhora	GO	36848410	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-02-22T18:17:57.530Z\\"}]"	2026-02-22 18:17:57.53
cmq848ixd00l3lz65y25tbb0a	user_007	user_007@email.com	\N	689.8	0	25	714.8	entregue	BR8143751732343	credit_card	Mastercard	0710	Pietro Moraes	Nicolas Silva Filho	Marginal Braga	4422	Apto 78	Nogueira do Sul	ES	03161621	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-26T10:46:19.057Z\\"}]"	2025-12-26 10:46:19.057
cmq848ixf00l5lz65ch5ev9bj	user_113	user_113@email.com	FRETE15	499.9	49.99	25	474.91	entregue	BR7552212255916	boleto	Elo	2203	Arthur Pereira	Maria Luiza Braga	Rodovia Franco	5083	Apto 63	Costa de Nossa Senhora	SC	38943845	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-10T12:19:37.819Z\\"}]"	2026-02-10 12:19:37.819
cmq848ixg00l7lz65zj8xgv06	user_028	user_028@email.com	\N	1469.6	0	25	1494.6	pago	\N	boleto	Mastercard	2442	Clara Santos	Pablo Xavier	Avenida Carla	7481	Apto 157	Albuquerque de Nossa Senhora	MG	60086267	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-03-16T10:23:19.832Z\\"}]"	2026-03-16 10:23:19.832
cmq848ixj00l9lz65ui9tepm5	user_037	user_037@email.com	\N	309.9	0	25	334.9	pendente	\N	credit_card	Amex	1591	Washington Carvalho	Yuri Santos	Travessa Hélio	5375	\N	Gabriel de Nossa Senhora	PR	69570250	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-01-12T02:42:42.316Z\\"}]"	2026-01-12 02:42:42.316
cmq848ixm00lblz65o729h5wh	user_031	user_031@email.com	FRETE15	1389.7	138.97	25	1275.73	entregue	BR6577695182796	pix	Mastercard	3367	Davi Santos	Pedro Henrique Martins	Rodovia Alice	8900	Apto 146	Franco do Norte	RJ	14835569	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-08T00:02:26.449Z\\"}]"	2026-01-08 00:02:26.449
cmq848ixp00ldlz650qujxv3w	user_007	user_007@email.com	\N	1089.7	0	25	1114.7	pendente	\N	boleto	Visa	4191	Lorena Carvalho	Ana Clara Reis	Alameda Suélen	549	\N	Franco do Norte	AM	08771768	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-05-27T07:44:25.586Z\\"}]"	2026-05-27 07:44:25.586
cmq848ixr00lflz65xmbep8er	user_005	user_005@email.com	FRETE15	449.9	44.99	25	429.91	entregue	BR0390649120428	pix	Elo	5049	Théo Batista	Helena Melo	Marginal Albuquerque	6613	Apto 51	Lorena de Nossa Senhora	MG	56321377	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-01T01:05:54.196Z\\"}]"	2025-12-01 01:05:54.196
cmq848ixs00lhlz656ujmi0sx	user_081	user_081@email.com	\N	479.9	0	25	504.9	pago	\N	credit_card	Elo	1099	Karla Moraes	Marcelo Nogueira	Rodovia Franco	335	\N	Laura do Sul	SC	18893233	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-03-18T10:28:51.706Z\\"}]"	2026-03-18 10:28:51.706
cmq848ixt00ljlz65588vdngu	user_022	user_022@email.com	\N	1419.6	0	25	1444.6	entregue	BR5002121090719	boleto	Elo	6098	Miguel Silva	Breno Batista	Marginal Albuquerque	7571	\N	Martins do Norte	PR	44753205	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-26T06:48:49.972Z\\"}]"	2026-05-26 06:48:49.972
cmq848ixv00lllz65th7ib12k	user_028	user_028@email.com	\N	369.9	0	25	394.9	pago	\N	pix	Mastercard	9224	Vitória Moreira	Aline Reis	Avenida Macedo	8470	\N	Norberto do Descoberto	AM	19693722	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-05-27T21:43:22.640Z\\"}]"	2026-05-27 21:43:22.64
cmq848ixx00lnlz658amegiyq	user_062	user_062@email.com	BEMVINDO10	399.9	39.99	25	384.91	entregue	BR6070287084866	boleto	Visa	6400	Sra. Maria Clara Moreira	Guilherme Santos	Rodovia Costa	2802	Apto 160	Eloá do Sul	RJ	85643914	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-02T14:55:28.591Z\\"}]"	2026-01-02 14:55:28.591
cmq848ixz00lplz65pbhezdr8	user_042	user_042@email.com	\N	789.8	0	25	814.8	entregue	BR7643364881163	credit_card	Amex	2977	Eloá Braga	Cecília Santos Jr.	Rodovia Moreira	9063	\N	Barros do Norte	GO	79205771	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-20T05:08:06.573Z\\"}]"	2026-02-20 05:08:06.573
cmq848iy300lrlz65uylmszcq	user_032	user_032@email.com	\N	869.8	0	25	894.8	entregue	BR2432917906204	boleto	Visa	5580	Murilo Souza	Laura Franco	Travessa Bernardo	9222	Apto 125	Martins de Nossa Senhora	DF	98114061	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-22T04:02:59.132Z\\"}]"	2026-01-22 04:02:59.132
cmq848iy600ltlz65qrfb6duq	user_063	user_063@email.com	\N	959.8	0	25	984.8	entregue	BR8981927929392	boleto	Visa	7542	Danilo Costa	Eduarda Martins	Rodovia Leonardo	890	\N	Emanuel de Nossa Senhora	SP	38151794	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-07T05:21:45.909Z\\"}]"	2026-02-07 05:21:45.909
cmq848iy800lvlz651yt2k23b	user_059	user_059@email.com	\N	2129.4	0	25	2154.4	pago	\N	credit_card	Mastercard	8366	Sarah Melo	Célia Saraiva	Marginal Silva	1942	Apto 196	Moreira do Norte	MA	50756541	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-05-31T22:56:43.603Z\\"}]"	2026-05-31 22:56:43.603
cmq848iya00lxlz65fbgwz0f4	user_034	user_034@email.com	\N	299.9	0	25	324.9	entregue	BR7722986045146	credit_card	Amex	8381	Cauã Oliveira	Félix Moraes	Marginal Silas	9728	Apto 144	Isaac do Sul	MG	79898423	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-26T22:24:51.508Z\\"}]"	2026-03-26 22:24:51.508
cmq848iyc00lzlz655oe5e68o	user_003	user_003@email.com	\N	899.8	0	25	924.8	pago	\N	pix	Amex	8174	Ana Clara Macedo	Pedro Henrique Barros	Rodovia Felipe	2465	Apto 48	César do Norte	CE	52000737	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-05-01T17:08:29.739Z\\"}]"	2026-05-01 17:08:29.739
cmq848iyd00m1lz65awujeiog	user_052	user_052@email.com	\N	609.8	0	25	634.8	pago	\N	pix	Elo	7568	Srta. Joana Nogueira	Sra. Meire Xavier	Avenida Maitê	4790	Apto 123	Martins do Sul	GO	82144557	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-03-04T21:12:48.167Z\\"}]"	2026-03-04 21:12:48.167
cmq848iyf00m3lz65p466cck6	user_062	user_062@email.com	\N	479.9	0	25	504.9	pendente	\N	credit_card	Elo	8495	Samuel Macedo	Yango Batista	Rodovia Lívia	5298	Apto 16	Santos do Norte	RS	42875604	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2025-12-18T07:00:49.821Z\\"}]"	2025-12-18 07:00:49.821
cmq848iyj00m5lz650cn7c5qw	user_024	user_024@email.com	\N	459.9	0	25	484.9	pago	\N	boleto	Elo	7133	Víctor Batista Neto	Maria Xavier	Alameda Moreira	7424	Apto 74	Hugo do Sul	PA	72584920	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-05-15T12:36:46.553Z\\"}]"	2026-05-15 12:36:46.553
cmq848iym00m7lz65eq9vaf7x	user_107	user_107@email.com	\N	1539.6	0	25	1564.6	cancelado	\N	pix	Visa	0270	Sr. Davi Lucca Braga	Lucca Costa	Avenida Franco	4559	Apto 160	Benício do Sul	PE	18894731	"[{\\"status\\":\\"cancelado\\",\\"at\\":\\"2026-05-17T14:08:23.022Z\\"}]"	2026-05-17 14:08:23.022
cmq848iyn00m9lz65fak1k4c3	user_054	user_054@email.com	FRETE15	379.9	37.99	25	366.91	cancelado	\N	credit_card	Amex	7902	Alessandra Pereira	Théo Martins	Avenida Gabriel	8523	\N	Santos de Nossa Senhora	DF	21172545	"[{\\"status\\":\\"cancelado\\",\\"at\\":\\"2025-12-23T01:47:03.602Z\\"}]"	2025-12-23 01:47:03.602
cmq848iyp00mblz65jqmr6mvv	user_106	user_106@email.com	FRETE15	1899.5	189.95	25	1734.55	entregue	BR6534546422037	boleto	Visa	9597	Bernardo Albuquerque	Márcia Saraiva Jr.	Travessa Melissa	970	Apto 168	Yuri do Descoberto	PA	23756718	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-13T02:31:46.396Z\\"}]"	2026-01-13 02:31:46.396
cmq848iyr00mdlz65k4nrp5xw	user_085	user_085@email.com	\N	1059.7	0	25	1084.7	pendente	\N	credit_card	Amex	8521	Esther Xavier	Matheus Saraiva	Avenida Nogueira	8891	\N	Gabriel do Norte	CE	72571869	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-04-12T12:25:24.163Z\\"}]"	2026-04-12 12:25:24.163
cmq848iys00mflz65g1wakerw	user_041	user_041@email.com	COPA2026	659.8	65.98	25	618.8199999999999	pago	\N	pix	Elo	2934	Dr. Breno Macedo	João Miguel Barros	Rua Saraiva	3608	\N	Elisa do Descoberto	SP	35576644	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-02-09T00:54:36.631Z\\"}]"	2026-02-09 00:54:36.631
cmq848iyu00mhlz65r1qdfa6n	user_050	user_050@email.com	BLACK30	1149.6	114.96	25	1059.64	entregue	BR8458832741910	credit_card	Elo	6333	Benjamin Carvalho	Morgana Barros	Travessa Saraiva	3151	\N	Sara do Descoberto	RS	15613926	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-04-22T12:41:07.018Z\\"}]"	2026-04-22 12:41:07.018
cmq848iyw00mjlz65i0kx3hp0	user_089	user_089@email.com	\N	1409.7	0	25	1434.7	pendente	\N	credit_card	Visa	8666	Joaquim Macedo	Emanuel Moreira Neto	Rua Marcos	8769	\N	Murilo do Sul	RS	28969397	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-01-26T23:28:44.309Z\\"}]"	2026-01-26 23:28:44.309
cmq848iyz00mllz65o8jcb496	user_006	user_006@email.com	\N	2029.5	0	25	2054.5	entregue	BR7569737034101	pix	Amex	9359	Marina Barros	Anthony Barros	Alameda Macedo	456	Apto 107	Bruna do Sul	MA	93367395	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-18T09:05:54.643Z\\"}]"	2026-01-18 09:05:54.643
cmq848iz300mnlz65t8ji9dd6	user_055	user_055@email.com	\N	619.8	0	25	644.8	cancelado	\N	credit_card	Amex	7371	João Pedro Oliveira	Aline Moreira	Alameda Reis	2048	Apto 127	Salvador de Nossa Senhora	ES	48723651	"[{\\"status\\":\\"cancelado\\",\\"at\\":\\"2026-04-18T22:56:01.083Z\\"}]"	2026-04-18 22:56:01.083
cmq848iz500mplz65qia18yaz	user_038	user_038@email.com	\N	1979.5	0	25	2004.5	pago	\N	boleto	Mastercard	9166	Isabel Reis	Sr. Benjamin Moraes	Rodovia Moreira	6002	\N	Souza do Sul	PE	56906266	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-02-08T21:18:53.794Z\\"}]"	2026-02-08 21:18:53.794
cmq848iz900mrlz65cxb68ikw	user_019	user_019@email.com	FUTSTORE20	259.9	25.99	25	258.91	pago	\N	pix	Elo	7997	Aline Batista	Antônio Costa	Travessa Martins	7648	\N	Maria Luiza do Sul	RS	24761615	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-05-28T19:35:59.742Z\\"}]"	2026-05-28 19:35:59.742
cmq848izb00mtlz65uzgx6mqp	user_064	user_064@email.com	FUTSTORE20	1999.4	199.94	25	1824.46	entregue	BR9038223647862	boleto	Mastercard	1051	Helena Nogueira	Sr. Enzo Xavier	Rodovia Karla	7071	\N	Pablo do Descoberto	PR	04162415	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-21T07:56:31.354Z\\"}]"	2026-05-21 07:56:31.354
cmq848ize00mvlz65kfw5a0bl	user_014	user_014@email.com	\N	329.9	0	25	354.9	entregue	BR4997643965209	credit_card	Mastercard	1808	Roberta Braga	Célia Martins	Travessa Félix	9516	\N	Rafaela de Nossa Senhora	CE	02571197	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-21T13:12:40.342Z\\"}]"	2025-12-21 13:12:40.342
cmq848izj00mxlz65cbiz0b98	user_071	user_071@email.com	\N	1739.6	0	25	1764.6	entregue	BR9474214766240	boleto	Amex	4016	Rafael Santos	Lívia Melo	Rodovia Danilo	5811	\N	Joana do Descoberto	PE	04393757	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-01T15:53:18.917Z\\"}]"	2026-05-01 15:53:18.917
cmq848izm00mzlz65zhxaane0	user_032	user_032@email.com	\N	1569.6	0	25	1594.6	pago	\N	boleto	Mastercard	5244	Théo Albuquerque	Maria Alice Martins	Travessa Sarah	8693	Apto 17	Albuquerque do Descoberto	MA	62802947	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-05-26T18:43:52.064Z\\"}]"	2026-05-26 18:43:52.064
cmq848izo00n1lz65sqyxlvyg	user_022	user_022@email.com	\N	669.8	0	25	694.8	enviado	BR4749247550329	credit_card	Amex	6358	Sr. César Macedo	Gael Oliveira	Marginal Nataniel	179	Apto 14	Saraiva do Norte	BA	69091389	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-02-15T12:27:34.584Z\\"}]"	2026-02-15 12:27:34.584
cmq848izq00n3lz65hxa92puc	user_061	user_061@email.com	\N	659.8	0	25	684.8	enviado	BR9178665881842	boleto	Mastercard	8204	Dra. Melissa Melo	Cauã Souza	Rua Reis	6395	\N	Márcia do Norte	DF	48328751	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-05-29T13:25:49.885Z\\"}]"	2026-05-29 13:25:49.885
cmq848izs00n5lz65usl7nmkw	user_026	user_026@email.com	\N	809.8	0	25	834.8	entregue	BR9229073091520	credit_card	Visa	0743	Suélen Reis	Isadora Oliveira	Rodovia Henrique	7273	Apto 21	Alice do Sul	BA	35018699	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-07T08:16:22.851Z\\"}]"	2025-12-07 08:16:22.851
cmq848izw00n7lz65o956mw4o	user_045	user_045@email.com	\N	759.8	0	25	784.8	pendente	\N	boleto	Elo	0312	Antônio Franco	Deneval Carvalho	Rodovia Ana Clara	7292	Apto 131	Pedro Henrique do Sul	DF	23499014	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2026-02-06T12:20:56.650Z\\"}]"	2026-02-06 12:20:56.65
cmq848j0100n9lz65erh5b1sd	user_013	user_013@email.com	\N	1369.7	0	25	1394.7	entregue	BR2406231845541	boleto	Visa	1723	Lara Oliveira	Fabiano Melo	Marginal Albuquerque	2441	Apto 107	Martins do Norte	PE	88956152	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-04-11T00:24:49.372Z\\"}]"	2026-04-11 00:24:49.372
cmq848j0500nblz65f0clhqkk	user_052	user_052@email.com	BEMVINDO10	719.8	71.98	25	672.8199999999999	entregue	BR5862577688546	boleto	Visa	9148	Laura Martins Neto	Yasmin Batista	Rua Valentina	9408	Apto 33	Ladislau do Descoberto	RJ	73964782	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-28T03:23:16.223Z\\"}]"	2026-01-28 03:23:16.223
cmq848j0800ndlz65xyzlssco	user_041	user_041@email.com	FRETE15	2079.5	207.95	25	1896.55	entregue	BR0983928875153	boleto	Amex	9089	Calebe Albuquerque	Yuri Franco	Rodovia Oliveira	8563	Apto 44	Marina do Descoberto	ES	22536014	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-04-07T10:13:28.996Z\\"}]"	2026-04-07 10:13:28.996
cmq848j0b00nflz65z510a3sl	user_041	user_041@email.com	\N	379.9	0	25	404.9	entregue	BR4777440962999	boleto	Amex	2882	Dra. Vitória Silva	Dra. Emanuelly Moreira	Avenida Gúbio	935	Apto 19	Rafaela do Sul	SC	83257910	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-06-04T05:25:07.509Z\\"}]"	2026-06-04 05:25:07.509
cmq848j0e00nhlz654tzscd5t	user_084	user_084@email.com	\N	1459.6	0	25	1484.6	enviado	BR2703361849421	credit_card	Elo	1352	Morgana Batista Filho	Vitória Silva	Avenida Costa	7737	\N	Melo do Sul	RJ	93882608	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-05-16T18:34:40.946Z\\"}]"	2026-05-16 18:34:40.946
cmq848j0h00njlz65pk94pm9i	user_021	user_021@email.com	\N	559.8	0	25	584.8	entregue	BR5435375852852	pix	Mastercard	8470	Vitória Braga	Maria Clara Reis	Travessa Souza	7930	\N	Franco do Sul	PA	83441948	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-12T11:38:16.687Z\\"}]"	2025-12-12 11:38:16.687
cmq848j0k00nllz65g7vbsd1i	user_023	user_023@email.com	\N	779.8	0	25	804.8	entregue	BR6522186118764	credit_card	Amex	7387	Júlia Batista	Núbia Barros	Marginal Melo	5950	\N	Enzo do Sul	DF	64622113	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-30T05:07:18.750Z\\"}]"	2026-03-30 05:07:18.75
cmq848j0p00nnlz65rzd22exg	user_092	user_092@email.com	\N	869.8	0	25	894.8	entregue	BR1244165200313	pix	Elo	2368	Júlio César Macedo	Sra. Yasmin Pereira	Rua Sara	5500	Apto 15	Moraes de Nossa Senhora	SP	52953481	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-06T08:53:13.332Z\\"}]"	2025-12-06 08:53:13.332
cmq848j0u00nplz65xfq36kx7	user_036	user_036@email.com	\N	1019.7	0	25	1044.7	entregue	BR9644613001474	pix	Visa	5269	Elisa Xavier	Sr. Frederico Batista	Rua Batista	2094	\N	Moreira do Sul	ES	53558947	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-07T17:02:59.845Z\\"}]"	2026-03-07 17:02:59.845
cmq848j0x00nrlz65k1crmqa1	user_012	user_012@email.com	FUTSTORE20	1149.7	114.97	25	1059.73	entregue	BR3492427720044	boleto	Mastercard	2845	Isis Nogueira	Vitor Moraes	Marginal Murilo	3512	Apto 137	Dalila do Descoberto	SC	94915277	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-25T06:42:29.592Z\\"}]"	2026-03-25 06:42:29.592
cmq848j1100ntlz65ja4z77vv	user_014	user_014@email.com	\N	1499.6	0	25	1524.6	entregue	BR8170168235287	credit_card	Mastercard	7360	Cauã Macedo	Arthur Macedo	Marginal Moreira	9008	Apto 115	Carvalho do Sul	CE	49269688	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-04-05T18:20:41.458Z\\"}]"	2026-04-05 18:20:41.458
cmq848j1600nvlz653rvq4785	user_044	user_044@email.com	\N	679.8	0	25	704.8	entregue	BR2996829111573	boleto	Mastercard	1468	Margarida Oliveira	Roberta Costa	Avenida Emanuelly	8328	\N	Albuquerque do Norte	SP	96387083	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-14T14:59:59.910Z\\"}]"	2025-12-14 14:59:59.91
cmq848j1b00nxlz65litv653t	user_018	user_018@email.com	\N	319.9	0	25	344.9	entregue	BR2221567623632	pix	Mastercard	0882	Dra. Marli Martins	Raul Macedo Jr.	Alameda Saraiva	8067	Apto 38	Oliveira do Sul	PA	28391574	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-06-07T02:54:02.210Z\\"}]"	2026-06-07 02:54:02.21
cmq848j1e00nzlz657775jh98	user_057	user_057@email.com	\N	1459.6	0	25	1484.6	entregue	BR1567200492216	boleto	Elo	8412	Lucas Pereira	Leonardo Costa	Travessa Barros	5815	Apto 194	Nogueira de Nossa Senhora	PR	05318978	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-11T04:51:33.037Z\\"}]"	2025-12-11 04:51:33.037
cmq848j1i00o1lz65fy8nklgw	user_026	user_026@email.com	\N	459.9	0	25	484.9	entregue	BR4006455244384	pix	Amex	8820	Dra. Felícia Oliveira	Maria Cecília Silva	Avenida Isabelly	9146	\N	Barros do Norte	BA	72784746	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-04-01T08:28:04.342Z\\"}]"	2026-04-01 08:28:04.342
cmq848j1l00o3lz651443vkv7	user_092	user_092@email.com	\N	1269.6	0	25	1294.6	entregue	BR2666438731005	credit_card	Mastercard	7277	Marli Martins	Víctor Braga	Alameda João Miguel	8140	\N	Souza do Descoberto	PA	42771817	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-03-13T10:53:28.337Z\\"}]"	2026-03-13 10:53:28.337
cmq848j1q00o5lz65w1tm6mi8	user_055	user_055@email.com	BLACK30	449.9	44.99	25	429.91	entregue	BR7050996988532	credit_card	Elo	1242	Víctor Oliveira	Srta. Dalila Costa	Travessa Carla	1732	Apto 132	Carvalho de Nossa Senhora	PA	16467569	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-14T17:44:10.395Z\\"}]"	2025-12-14 17:44:10.395
cmq848j1v00o7lz654qdqwx34	user_036	user_036@email.com	\N	819.8	0	25	844.8	enviado	BR6812570943217	boleto	Mastercard	9846	Srta. Maitê Pereira	Eduardo Moraes	Alameda Ana Clara	26	Apto 159	Braga do Norte	CE	16917031	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-04-24T20:10:24.792Z\\"}]"	2026-04-24 20:10:24.792
cmq848j2100o9lz65evrot37m	user_043	user_043@email.com	\N	289.9	0	25	314.9	entregue	BR2854142980524	boleto	Elo	3286	Elisa Xavier	Lorraine Macedo Neto	Marginal Barros	9583	Apto 125	Reis do Sul	MG	54103397	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-15T02:42:53.661Z\\"}]"	2026-02-15 02:42:53.661
cmq848j2700oblz657b9c81fs	user_080	user_080@email.com	\N	1349.7	0	25	1374.7	entregue	BR0885587859918	pix	Mastercard	6058	Júlia Martins	Lorraine Santos	Alameda Reis	5580	Apto 34	Maria Helena do Descoberto	PR	72352804	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-18T09:30:30.946Z\\"}]"	2026-05-18 09:30:30.946
cmq848j2c00odlz65q4ikyov7	user_102	user_102@email.com	\N	1699.6	0	25	1724.6	entregue	BR1024762598397	credit_card	Visa	1715	Sophia Souza	Larissa Souza	Rua Sílvia	6929	\N	Valentina do Descoberto	AM	93069911	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2025-12-06T05:59:30.071Z\\"}]"	2025-12-06 05:59:30.071
cmq848j2i00oflz65dmmf51ig	user_068	user_068@email.com	COPA2026	1019.7	101.97	25	942.7299999999999	enviado	BR6500212334006	pix	Mastercard	6846	Salvador Oliveira Neto	João Miguel Martins	Rua Albuquerque	8208	Apto 160	Valentina de Nossa Senhora	ES	66596481	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-05-14T16:56:36.736Z\\"}]"	2026-05-14 16:56:36.736
cmq848j2o00ohlz65dk5pu6vt	user_066	user_066@email.com	\N	1779.5	0	25	1804.5	pago	\N	pix	Visa	1991	Isabel Carvalho	Morgana Oliveira	Rodovia Moreira	913	Apto 117	Xavier do Descoberto	MG	60051015	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-02-15T06:02:38.488Z\\"}]"	2026-02-15 06:02:38.488
cmq848j2t00ojlz65cdxxj9pd	user_085	user_085@email.com	BLACK30	459.9	45.99	25	438.91	pago	\N	boleto	Visa	9230	Marina Nogueira	Enzo Albuquerque	Rua Bruna	9148	Apto 108	Franco do Descoberto	SP	31565438	"[{\\"status\\":\\"pago\\",\\"at\\":\\"2026-05-28T04:26:43.302Z\\"}]"	2026-05-28 04:26:43.302
cmq848j2x00ollz65crqwveit	user_027	user_027@email.com	\N	1379.6	0	25	1404.6	enviado	BR9830558953105	pix	Amex	5968	Rafaela Braga Filho	Larissa Oliveira	Travessa Pietro	8972	Apto 47	Bryan de Nossa Senhora	ES	04806926	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-05-27T16:20:19.569Z\\"}]"	2026-05-27 16:20:19.569
cmq848j3100onlz65mgevz91o	user_118	user_118@email.com	BEMVINDO10	1439.6	143.96	25	1320.64	entregue	BR3017367590798	credit_card	Mastercard	1673	Nataniel Saraiva	Maria Alice Moreira	Travessa Moreira	1143	\N	Elisa do Sul	RJ	73052586	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-01-20T11:48:12.511Z\\"}]"	2026-01-20 11:48:12.511
cmq848j3600oplz65ylbg86j7	user_077	user_077@email.com	\N	749.8	0	25	774.8	pendente	\N	pix	Amex	5635	Maria Eduarda Moraes	Talita Franco	Travessa Franco	3928	Apto 167	Maria Júlia do Norte	MG	45145928	"[{\\"status\\":\\"pendente\\",\\"at\\":\\"2025-12-20T15:03:00.643Z\\"}]"	2025-12-20 15:03:00.643
cmq848j3800orlz65i2a3u5e8	user_078	user_078@email.com	COPA2026	299.9	29.99	25	294.91	enviado	BR3361884820645	boleto	Amex	6701	Heitor Franco	Maria Alice Barros	Rodovia Célia	5487	Apto 10	Matheus de Nossa Senhora	BA	42368181	"[{\\"status\\":\\"enviado\\",\\"at\\":\\"2026-02-11T11:22:16.804Z\\"}]"	2026-02-11 11:22:16.804
cmq848j3a00otlz65ww9gkus8	user_026	user_026@email.com	\N	479.9	0	25	504.9	entregue	BR9286873723192	pix	Mastercard	9378	Isadora Souza	Roberta Nogueira	Marginal Théo	1720	Apto 167	Yasmin de Nossa Senhora	PA	91376558	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-05-17T00:12:17.725Z\\"}]"	2026-05-17 00:12:17.725
cmq848j3b00ovlz65dp9lxnzk	user_029	user_029@email.com	\N	589.8	0	25	614.8	entregue	BR6060795624812	pix	Elo	3903	Dr. Deneval Braga	Júlio César Franco	Rodovia Pablo	464	\N	Emanuel de Nossa Senhora	AM	42185882	"[{\\"status\\":\\"entregue\\",\\"at\\":\\"2026-02-20T12:06:11.203Z\\"}]"	2026-02-20 12:06:11.203
\.


--
-- Data for Name: OrderItem; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."OrderItem" (id, "orderId", "productId", name, size, "unitPrice", quantity, "imageUrl") FROM stdin;
249	cmq848it500i9lz65ikq63i80	cmq848ilf005ilz65bdq5gcj3	Brasil Retrô 70 Camisa I (Home) 24/25	P	279.9	1	/jerseys/placeholder.jpg
250	cmq848itc00iblz65livqt9c5	cmq848ihv001alz657eusus9a	Vasco Camisa II (Away) 24/25	M	299.9	1	/jerseys/placeholder.jpg
251	cmq848itf00idlz65df7sbixf	cmq848ikk004ilz65atys1fdm	Seleção Portugal Camisa II (Away) 24/25	G	379.9	1	/jerseys/placeholder.jpg
252	cmq848itf00idlz65df7sbixf	cmq848ile005glz654vu28kop	Flamengo Retrô 81 Camisa III (Third) 24/25	GG	279.9	2	/jerseys/placeholder.jpg
253	cmq848itf00idlz65df7sbixf	cmq848ilv005ylz65yszzgfgb	Chelsea Camisa I (Home) 24/25	GG	459.9	1	/jerseys/placeholder.jpg
254	cmq848itl00iflz6595hhlyrj	cmq848iie001wlz65u8ntejt8	Cruzeiro Camisa II (Away) 24/25	P	299.9	2	/jerseys/placeholder.jpg
255	cmq848itn00ihlz65x4aoy3ar	cmq848iir0028lz65h70y18gn	Bahia Camisa III (Third) 24/25	M	309.9	2	/jerseys/placeholder.jpg
256	cmq848itn00ihlz65x4aoy3ar	cmq848ijh0036lz65wsfy2t1j	Bayern de Munique Camisa III (Third) 24/25	GG	499.9	1	/jerseys/placeholder.jpg
257	cmq848itp00ijlz655ndot5yl	cmq848ik1003ulz653oni9m29	Seleção Brasileira Camisa I (Home) 24/25	GG	389.9	1	/jerseys/placeholder.jpg
258	cmq848itr00illz65k87uxr4y	cmq848iji0038lz657sbpyxzb	PSG Camisa I (Home) 24/25	P	479.9	1	/jerseys/placeholder.jpg
259	cmq848itr00illz65k87uxr4y	cmq848ilv005ylz65yszzgfgb	Chelsea Camisa I (Home) 24/25	P	459.9	2	/jerseys/placeholder.jpg
260	cmq848itt00inlz65yoczfnn0	cmq848im00064lz65vvsub73c	Arsenal Camisa II (Away) 24/25	M	459.9	1	/jerseys/placeholder.jpg
261	cmq848itw00iplz65ztydciuv	cmq848ikv004wlz65zp7bsxhi	Seleção Inglaterra Camisa I (Home) 24/25	M	369.9	1	/jerseys/placeholder.jpg
262	cmq848iu000irlz65o8902je4	cmq848iji0038lz657sbpyxzb	PSG Camisa I (Home) 24/25	P	479.9	1	/jerseys/placeholder.jpg
263	cmq848iu000irlz65o8902je4	cmq848ijz003qlz65dhquij4u	Inter de Milão Camisa II (Away) 24/25	G	449.9	2	/jerseys/placeholder.jpg
264	cmq848iu200itlz65siyd733v	cmq848ike004alz65zfska0qx	Seleção França Camisa I (Home) 24/25	GG	379.9	1	/jerseys/placeholder.jpg
265	cmq848iu200itlz65siyd733v	cmq848ili005klz65un7jjek4	Brasil Retrô 70 Camisa II (Away) 24/25	P	279.9	2	/jerseys/placeholder.jpg
266	cmq848iu400ivlz65fpjqwil8	cmq848ij9002wlz659yg4uu4y	Liverpool Camisa I (Home) 24/25	GG	459.9	1	/jerseys/placeholder.jpg
267	cmq848iu400ivlz65fpjqwil8	cmq848ihm0014lz65xbhdl0sk	Internacional Camisa II (Away) 24/25	GG	309.9	1	/jerseys/placeholder.jpg
268	cmq848iu600ixlz6548rvqso5	cmq848ije0032lz6553k06x48	Bayern de Munique Camisa I (Home) 24/25	GG	479.9	1	/jerseys/placeholder.jpg
269	cmq848iu700izlz65ygufdo5l	cmq848ihx001clz659v8onw95	Vasco Camisa III (Third) 24/25	M	319.9	1	/jerseys/placeholder.jpg
270	cmq848iu700izlz65ygufdo5l	cmq848im10066lz65y0qob3c4	Arsenal Camisa III (Third) 24/25	M	479.9	1	/jerseys/placeholder.jpg
271	cmq848iu900j1lz65ncvvpnsz	cmq848ik50040lz65iqavat35	Seleção Argentina Camisa I (Home) 24/25	GG	389.9	1	/jerseys/placeholder.jpg
272	cmq848iu900j1lz65ncvvpnsz	cmq848ikc0048lz6576k666m5	Seleção Alemanha Camisa III (Third) 24/25	GG	399.9	1	/jerseys/placeholder.jpg
273	cmq848iuc00j3lz65bcrmx0k8	cmq848iie001wlz65u8ntejt8	Cruzeiro Camisa II (Away) 24/25	P	299.9	1	/jerseys/placeholder.jpg
274	cmq848iuc00j3lz65bcrmx0k8	cmq848ika0046lz65a6qi9yx5	Seleção Alemanha Camisa II (Away) 24/25	G	379.9	1	/jerseys/placeholder.jpg
275	cmq848iug00j5lz65pe2jg1ub	cmq848ikk004ilz65atys1fdm	Seleção Portugal Camisa II (Away) 24/25	M	379.9	1	/jerseys/placeholder.jpg
276	cmq848iug00j5lz65pe2jg1ub	cmq848ilq005slz651wha1szo	Borussia Dortmund Camisa I (Home) 24/25	P	449.9	1	/jerseys/placeholder.jpg
277	cmq848iug00j5lz65pe2jg1ub	cmq848ikn004mlz65b34aur70	Seleção Espanha Camisa I (Home) 24/25	G	369.9	1	/jerseys/placeholder.jpg
278	cmq848iui00j7lz655zhjnsmv	cmq848ijb002ylz65ahgqa8zj	Liverpool Camisa II (Away) 24/25	P	459.9	1	/jerseys/placeholder.jpg
279	cmq848iuk00j9lz65oqqcvfyy	cmq848im4006alz65yqqlc42q	Atlético de Madrid Camisa II (Away) 24/25	G	449.9	2	/jerseys/placeholder.jpg
280	cmq848iuk00j9lz65oqqcvfyy	cmq848iij0020lz65icy2v5u5	Santos Camisa II (Away) 24/25	P	299.9	1	/jerseys/placeholder.jpg
281	cmq848ium00jblz65hskdikov	cmq848ike004alz65zfska0qx	Seleção França Camisa I (Home) 24/25	G	379.9	1	/jerseys/placeholder.jpg
282	cmq848ium00jblz65hskdikov	cmq848iim0024lz653bqj3pmx	Bahia Camisa I (Home) 24/25	M	289.9	1	/jerseys/placeholder.jpg
283	cmq848iun00jdlz652knhe2s9	cmq848ilv005ylz65yszzgfgb	Chelsea Camisa I (Home) 24/25	P	459.9	1	/jerseys/placeholder.jpg
284	cmq848iun00jdlz652knhe2s9	cmq848igs000clz65lnk7697z	Flamengo Camisa I (Home) 24/25	P	349.9	1	/jerseys/placeholder.jpg
285	cmq848iup00jflz658euo1qmh	cmq848ik50040lz65iqavat35	Seleção Argentina Camisa I (Home) 24/25	M	389.9	2	/jerseys/placeholder.jpg
286	cmq848iup00jflz658euo1qmh	cmq848il9005alz65fbsfrfd8	Seleção México Camisa III (Third) 24/25	P	369.9	1	/jerseys/placeholder.jpg
287	cmq848iut00jhlz65tlix4m0l	cmq848ij3002olz65pe3rcpx3	FC Barcelona Camisa II (Away) 24/25	GG	499.9	1	/jerseys/placeholder.jpg
288	cmq848iut00jhlz65tlix4m0l	cmq848il20052lz6542nm8a9p	Seleção Japão Camisa II (Away) 24/25	G	349.9	1	/jerseys/placeholder.jpg
289	cmq848iut00jhlz65tlix4m0l	cmq848ihm0014lz65xbhdl0sk	Internacional Camisa II (Away) 24/25	P	309.9	1	/jerseys/placeholder.jpg
290	cmq848iuy00jjlz65qon3bzh4	cmq848iht0018lz65i6s6humm	Vasco Camisa I (Home) 24/25	GG	299.9	2	/jerseys/placeholder.jpg
291	cmq848iuy00jjlz65qon3bzh4	cmq848ijp003elz65vw586mhy	Juventus Camisa I (Home) 24/25	G	459.9	1	/jerseys/placeholder.jpg
292	cmq848iuy00jjlz65qon3bzh4	cmq848ilo005qlz657qbcleae	Santos Retrô Pelé Camisa II (Away) 24/25	P	269.9	1	/jerseys/placeholder.jpg
293	cmq848iuy00jjlz65qon3bzh4	cmq848ihv001alz657eusus9a	Vasco Camisa II (Away) 24/25	P	299.9	1	/jerseys/placeholder.jpg
294	cmq848iv300jllz654jv96sfh	cmq848ijr003glz651qntef1v	Juventus Camisa II (Away) 24/25	M	459.9	2	/jerseys/placeholder.jpg
295	cmq848iv300jllz654jv96sfh	cmq848ii6001olz65adf9giip	Atlético-MG Camisa I (Home) 24/25	P	309.9	1	/jerseys/placeholder.jpg
296	cmq848iv300jllz654jv96sfh	cmq848ilb005clz65kg0tdzo3	Flamengo Retrô 81 Camisa I (Home) 24/25	GG	259.9	1	/jerseys/placeholder.jpg
297	cmq848iv600jnlz65mvzs49qd	cmq848ik0003slz65tua1l71k	Inter de Milão Camisa III (Third) 24/25	G	469.9	2	/jerseys/placeholder.jpg
298	cmq848iv600jnlz65mvzs49qd	cmq848ijb002ylz65ahgqa8zj	Liverpool Camisa II (Away) 24/25	P	459.9	2	/jerseys/placeholder.jpg
299	cmq848iv600jnlz65mvzs49qd	cmq848ili005klz65un7jjek4	Brasil Retrô 70 Camisa II (Away) 24/25	M	279.9	1	/jerseys/placeholder.jpg
300	cmq848iv900jplz65cl1p86ui	cmq848ihz001elz655wdbodk7	Botafogo Camisa I (Home) 24/25	M	299.9	1	/jerseys/placeholder.jpg
301	cmq848ive00jrlz65ed1xt7nq	cmq848ij6002slz650iblsiyq	Manchester City Camisa I (Home) 24/25	M	459.9	2	/jerseys/placeholder.jpg
302	cmq848ivh00jtlz65z8gk6d9q	cmq848ik1003ulz653oni9m29	Seleção Brasileira Camisa I (Home) 24/25	GG	389.9	2	/jerseys/placeholder.jpg
303	cmq848ivh00jtlz65z8gk6d9q	cmq848ii5001mlz6549m4ra8a	Fluminense Camisa III (Third) 24/25	GG	319.9	2	/jerseys/placeholder.jpg
304	cmq848ivl00jvlz65tdudivac	cmq848ij8002ulz65bg2e9a8o	Manchester City Camisa II (Away) 24/25	M	459.9	1	/jerseys/placeholder.jpg
305	cmq848ivn00jxlz65rw5hjmft	cmq848il20052lz6542nm8a9p	Seleção Japão Camisa II (Away) 24/25	P	349.9	1	/jerseys/placeholder.jpg
306	cmq848ivn00jxlz65rw5hjmft	cmq848ijc0030lz65k5f1ruxs	Liverpool Camisa III (Third) 24/25	M	479.9	1	/jerseys/placeholder.jpg
307	cmq848ivr00jzlz652l5i52c3	cmq848ihm0014lz65xbhdl0sk	Internacional Camisa II (Away) 24/25	GG	309.9	1	/jerseys/placeholder.jpg
308	cmq848ivr00jzlz652l5i52c3	cmq848ije0032lz6553k06x48	Bayern de Munique Camisa I (Home) 24/25	GG	479.9	1	/jerseys/placeholder.jpg
309	cmq848ivv00k1lz65z3okgg8h	cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	M	459.9	2	/jerseys/placeholder.jpg
310	cmq848ivv00k1lz65z3okgg8h	cmq848iit002alz65y173ku0u	Fortaleza Camisa I (Home) 24/25	GG	289.9	2	/jerseys/placeholder.jpg
311	cmq848ivy00k3lz653bpabtwa	cmq848im4006alz65yqqlc42q	Atlético de Madrid Camisa II (Away) 24/25	P	449.9	1	/jerseys/placeholder.jpg
312	cmq848ivy00k3lz653bpabtwa	cmq848iht0018lz65i6s6humm	Vasco Camisa I (Home) 24/25	GG	299.9	1	/jerseys/placeholder.jpg
313	cmq848ivy00k3lz653bpabtwa	cmq848ij8002ulz65bg2e9a8o	Manchester City Camisa II (Away) 24/25	G	459.9	1	/jerseys/placeholder.jpg
314	cmq848ivy00k3lz653bpabtwa	cmq848ije0032lz6553k06x48	Bayern de Munique Camisa I (Home) 24/25	P	479.9	2	/jerseys/placeholder.jpg
315	cmq848iw000k5lz65tmh7mejf	cmq848ijp003elz65vw586mhy	Juventus Camisa I (Home) 24/25	GG	459.9	1	/jerseys/placeholder.jpg
316	cmq848iw000k5lz65tmh7mejf	cmq848iky004ylz65gaaevnn2	Seleção Inglaterra Camisa II (Away) 24/25	M	369.9	1	/jerseys/placeholder.jpg
317	cmq848iw200k7lz659m1u0m3r	cmq848ii2001ilz65yyaupzh9	Fluminense Camisa I (Home) 24/25	P	299.9	1	/jerseys/placeholder.jpg
318	cmq848iw200k7lz659m1u0m3r	cmq848ii5001mlz6549m4ra8a	Fluminense Camisa III (Third) 24/25	M	319.9	1	/jerseys/placeholder.jpg
319	cmq848iw500k9lz65w52cxj6w	cmq848iik0022lz65hx9rzq5u	Santos Camisa III (Third) 24/25	M	319.9	1	/jerseys/placeholder.jpg
320	cmq848iw900kblz65l26lo7su	cmq848iie001wlz65u8ntejt8	Cruzeiro Camisa II (Away) 24/25	M	299.9	1	/jerseys/placeholder.jpg
321	cmq848iw900kblz65l26lo7su	cmq848iic001ulz65hgqi8ctd	Cruzeiro Camisa I (Home) 24/25	P	299.9	2	/jerseys/placeholder.jpg
322	cmq848iw900kblz65l26lo7su	cmq848ihx001clz659v8onw95	Vasco Camisa III (Third) 24/25	P	319.9	2	/jerseys/placeholder.jpg
323	cmq848iwd00kdlz657i68mzlq	cmq848ilv005ylz65yszzgfgb	Chelsea Camisa I (Home) 24/25	G	459.9	1	/jerseys/placeholder.jpg
324	cmq848iwd00kdlz657i68mzlq	cmq848ijp003elz65vw586mhy	Juventus Camisa I (Home) 24/25	GG	459.9	1	/jerseys/placeholder.jpg
325	cmq848iwf00kflz65cgzsxcve	cmq848iir0028lz65h70y18gn	Bahia Camisa III (Third) 24/25	P	309.9	1	/jerseys/placeholder.jpg
326	cmq848iwf00kflz65cgzsxcve	cmq848ihq0016lz65zw3mbwpe	Internacional Camisa III (Third) 24/25	M	329.9	2	/jerseys/placeholder.jpg
327	cmq848iwf00kflz65cgzsxcve	cmq848igy000elz65szym5a03	Flamengo Camisa II (Away) 24/25	GG	349.9	2	/jerseys/placeholder.jpg
328	cmq848iwi00khlz652fjlgtnc	cmq848iim0024lz653bqj3pmx	Bahia Camisa I (Home) 24/25	GG	289.9	2	/jerseys/placeholder.jpg
329	cmq848iwi00khlz652fjlgtnc	cmq848ilv005ylz65yszzgfgb	Chelsea Camisa I (Home) 24/25	P	459.9	2	/jerseys/placeholder.jpg
330	cmq848iwl00kjlz6509btyvv7	cmq848ijz003qlz65dhquij4u	Inter de Milão Camisa II (Away) 24/25	G	449.9	1	/jerseys/placeholder.jpg
331	cmq848iwl00kjlz6509btyvv7	cmq848iim0024lz653bqj3pmx	Bahia Camisa I (Home) 24/25	M	289.9	1	/jerseys/placeholder.jpg
332	cmq848iwl00kjlz6509btyvv7	cmq848iiw002elz65wl2zq8ty	Fortaleza Camisa III (Third) 24/25	P	309.9	1	/jerseys/placeholder.jpg
333	cmq848iwp00kllz65v0uxycd4	cmq848ihm0014lz65xbhdl0sk	Internacional Camisa II (Away) 24/25	GG	309.9	2	/jerseys/placeholder.jpg
334	cmq848iwp00kllz65v0uxycd4	cmq848ih2000ilz65lyxr140a	Palmeiras Camisa I (Home) 24/25	G	329.9	1	/jerseys/placeholder.jpg
335	cmq848iws00knlz65khwmvu79	cmq848iia001slz65fc01vzde	Atlético-MG Camisa III (Third) 24/25	G	329.9	1	/jerseys/placeholder.jpg
336	cmq848iws00knlz65khwmvu79	cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	GG	459.9	1	/jerseys/placeholder.jpg
337	cmq848iwv00kplz659us0k4lh	cmq848ijz003qlz65dhquij4u	Inter de Milão Camisa II (Away) 24/25	M	449.9	1	/jerseys/placeholder.jpg
338	cmq848iwx00krlz65q020xvi2	cmq848iji0038lz657sbpyxzb	PSG Camisa I (Home) 24/25	M	479.9	1	/jerseys/placeholder.jpg
339	cmq848iwx00krlz65q020xvi2	cmq848ihe000wlz65o8uu03fy	São Paulo Camisa III (Third) 24/25	G	339.9	1	/jerseys/placeholder.jpg
340	cmq848iwx00krlz65q020xvi2	cmq848ih0000glz65c18vd6k5	Flamengo Camisa III (Third) 24/25	M	369.9	1	/jerseys/placeholder.jpg
341	cmq848iwx00krlz65q020xvi2	cmq848ij0002klz65fxbxd314	Real Madrid Camisa III (Third) 24/25	M	519.9	2	/jerseys/placeholder.jpg
342	cmq848iwz00ktlz65zq87bmxq	cmq848ile005glz654vu28kop	Flamengo Retrô 81 Camisa III (Third) 24/25	G	279.9	1	/jerseys/placeholder.jpg
343	cmq848ix200kvlz651uwqfyjz	cmq848ijr003glz651qntef1v	Juventus Camisa II (Away) 24/25	M	459.9	2	/jerseys/placeholder.jpg
344	cmq848ix500kxlz65z0ufk33v	cmq848ii2001ilz65yyaupzh9	Fluminense Camisa I (Home) 24/25	P	299.9	1	/jerseys/placeholder.jpg
345	cmq848ix900kzlz65ldrrbp41	cmq848ilq005slz651wha1szo	Borussia Dortmund Camisa I (Home) 24/25	M	449.9	1	/jerseys/placeholder.jpg
346	cmq848ix900kzlz65ldrrbp41	cmq848ilt005wlz65964p7y2x	Borussia Dortmund Camisa III (Third) 24/25	G	469.9	1	/jerseys/placeholder.jpg
347	cmq848ixa00l1lz65i43t0gar	cmq848iha000slz65x7kqdxj9	São Paulo Camisa I (Home) 24/25	M	319.9	2	/jerseys/placeholder.jpg
348	cmq848ixa00l1lz65i43t0gar	cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	M	459.9	2	/jerseys/placeholder.jpg
349	cmq848ixd00l3lz65y25tbb0a	cmq848ih5000mlz650gs0sigx	Corinthians Camisa I (Home) 24/25	M	319.9	1	/jerseys/placeholder.jpg
350	cmq848ixd00l3lz65y25tbb0a	cmq848iks004slz65ehkzn2hc	Seleção Itália Camisa I (Home) 24/25	P	369.9	1	/jerseys/placeholder.jpg
351	cmq848ixf00l5lz65ch5ev9bj	cmq848ijo003clz65wfuym48q	PSG Camisa III (Third) 24/25	P	499.9	1	/jerseys/placeholder.jpg
352	cmq848ixg00l7lz65zj8xgv06	cmq848ikm004klz65hb0e9zxy	Seleção Portugal Camisa III (Third) 24/25	M	399.9	2	/jerseys/placeholder.jpg
353	cmq848ixg00l7lz65zj8xgv06	cmq848ii5001mlz6549m4ra8a	Fluminense Camisa III (Third) 24/25	P	319.9	1	/jerseys/placeholder.jpg
354	cmq848ixg00l7lz65zj8xgv06	cmq848il20052lz6542nm8a9p	Seleção Japão Camisa II (Away) 24/25	M	349.9	1	/jerseys/placeholder.jpg
355	cmq848ixj00l9lz65ui9tepm5	cmq848ihf000ylz651yn37u7c	Grêmio Camisa I (Home) 24/25	GG	309.9	1	/jerseys/placeholder.jpg
356	cmq848ixm00lblz65o729h5wh	cmq848ils005ulz653byla82q	Borussia Dortmund Camisa II (Away) 24/25	M	449.9	1	/jerseys/placeholder.jpg
357	cmq848ixm00lblz65o729h5wh	cmq848ik0003slz65tua1l71k	Inter de Milão Camisa III (Third) 24/25	GG	469.9	2	/jerseys/placeholder.jpg
358	cmq848ixp00ldlz650qujxv3w	cmq848ijx003olz659ubwcr00	Inter de Milão Camisa I (Home) 24/25	P	449.9	1	/jerseys/placeholder.jpg
359	cmq848ixp00ldlz650qujxv3w	cmq848iha000slz65x7kqdxj9	São Paulo Camisa I (Home) 24/25	G	319.9	2	/jerseys/placeholder.jpg
360	cmq848ixr00lflz65xmbep8er	cmq848ils005ulz653byla82q	Borussia Dortmund Camisa II (Away) 24/25	GG	449.9	1	/jerseys/placeholder.jpg
361	cmq848ixs00lhlz656ujmi0sx	cmq848iji0038lz657sbpyxzb	PSG Camisa I (Home) 24/25	M	479.9	1	/jerseys/placeholder.jpg
362	cmq848ixt00ljlz65588vdngu	cmq848ika0046lz65a6qi9yx5	Seleção Alemanha Camisa II (Away) 24/25	GG	379.9	2	/jerseys/placeholder.jpg
363	cmq848ixt00ljlz65588vdngu	cmq848ih2000ilz65lyxr140a	Palmeiras Camisa I (Home) 24/25	G	329.9	2	/jerseys/placeholder.jpg
364	cmq848ixv00lllz65th7ib12k	cmq848ikt004ulz651faf9oi1	Seleção Itália Camisa II (Away) 24/25	GG	369.9	1	/jerseys/placeholder.jpg
365	cmq848ixx00lnlz658amegiyq	cmq848ikm004klz65hb0e9zxy	Seleção Portugal Camisa III (Third) 24/25	P	399.9	1	/jerseys/placeholder.jpg
366	cmq848ixz00lplz65pbhezdr8	cmq848ijp003elz65vw586mhy	Juventus Camisa I (Home) 24/25	P	459.9	1	/jerseys/placeholder.jpg
367	cmq848ixz00lplz65pbhezdr8	cmq848ihq0016lz65zw3mbwpe	Internacional Camisa III (Third) 24/25	GG	329.9	1	/jerseys/placeholder.jpg
368	cmq848iy300lrlz65uylmszcq	cmq848il40054lz65pt2vtbp1	Seleção Japão Camisa III (Third) 24/25	GG	369.9	1	/jerseys/placeholder.jpg
369	cmq848iy300lrlz65uylmszcq	cmq848ijh0036lz65wsfy2t1j	Bayern de Munique Camisa III (Third) 24/25	GG	499.9	1	/jerseys/placeholder.jpg
370	cmq848iy600ltlz65qrfb6duq	cmq848iji0038lz657sbpyxzb	PSG Camisa I (Home) 24/25	GG	479.9	2	/jerseys/placeholder.jpg
371	cmq848iy800lvlz651yt2k23b	cmq848il60056lz65m1n86f89	Seleção México Camisa I (Home) 24/25	P	349.9	1	/jerseys/placeholder.jpg
372	cmq848iy800lvlz651yt2k23b	cmq848ihf000ylz651yn37u7c	Grêmio Camisa I (Home) 24/25	M	309.9	2	/jerseys/placeholder.jpg
373	cmq848iy800lvlz651yt2k23b	cmq848ikj004glz6503ai64kp	Seleção Portugal Camisa I (Home) 24/25	G	379.9	1	/jerseys/placeholder.jpg
374	cmq848iy800lvlz651yt2k23b	cmq848ik1003ulz653oni9m29	Seleção Brasileira Camisa I (Home) 24/25	GG	389.9	2	/jerseys/placeholder.jpg
375	cmq848iya00lxlz65fbgwz0f4	cmq848iht0018lz65i6s6humm	Vasco Camisa I (Home) 24/25	G	299.9	1	/jerseys/placeholder.jpg
376	cmq848iyc00lzlz655oe5e68o	cmq848ilq005slz651wha1szo	Borussia Dortmund Camisa I (Home) 24/25	M	449.9	1	/jerseys/placeholder.jpg
377	cmq848iyc00lzlz655oe5e68o	cmq848im20068lz65u5y3t9r1	Atlético de Madrid Camisa I (Home) 24/25	M	449.9	1	/jerseys/placeholder.jpg
378	cmq848iyd00m1lz65awujeiog	cmq848ihj0012lz655nqbfi4h	Internacional Camisa I (Home) 24/25	M	309.9	1	/jerseys/placeholder.jpg
379	cmq848iyd00m1lz65awujeiog	cmq848iig001ylz65bxct2alm	Santos Camisa I (Home) 24/25	G	299.9	1	/jerseys/placeholder.jpg
380	cmq848iyf00m3lz65p466cck6	cmq848im10066lz65y0qob3c4	Arsenal Camisa III (Third) 24/25	GG	479.9	1	/jerseys/placeholder.jpg
381	cmq848iyj00m5lz650cn7c5qw	cmq848ij6002slz650iblsiyq	Manchester City Camisa I (Home) 24/25	G	459.9	1	/jerseys/placeholder.jpg
382	cmq848iym00m7lz65eq9vaf7x	cmq848ijx003olz659ubwcr00	Inter de Milão Camisa I (Home) 24/25	GG	449.9	1	/jerseys/placeholder.jpg
383	cmq848iym00m7lz65eq9vaf7x	cmq848ilb005clz65kg0tdzo3	Flamengo Retrô 81 Camisa I (Home) 24/25	G	259.9	1	/jerseys/placeholder.jpg
384	cmq848iym00m7lz65eq9vaf7x	cmq848il9005alz65fbsfrfd8	Seleção México Camisa III (Third) 24/25	G	369.9	1	/jerseys/placeholder.jpg
385	cmq848iym00m7lz65eq9vaf7x	cmq848ilw0060lz65kz1v9b1j	Chelsea Camisa II (Away) 24/25	P	459.9	1	/jerseys/placeholder.jpg
386	cmq848iyn00m9lz65fak1k4c3	cmq848ik90044lz65z6mok81k	Seleção Alemanha Camisa I (Home) 24/25	G	379.9	1	/jerseys/placeholder.jpg
387	cmq848iyp00mblz65jqmr6mvv	cmq848iht0018lz65i6s6humm	Vasco Camisa I (Home) 24/25	P	299.9	1	/jerseys/placeholder.jpg
388	cmq848iyp00mblz65jqmr6mvv	cmq848ika0046lz65a6qi9yx5	Seleção Alemanha Camisa II (Away) 24/25	M	379.9	2	/jerseys/placeholder.jpg
389	cmq848iyp00mblz65jqmr6mvv	cmq848ijx003olz659ubwcr00	Inter de Milão Camisa I (Home) 24/25	P	449.9	1	/jerseys/placeholder.jpg
390	cmq848iyp00mblz65jqmr6mvv	cmq848ik50040lz65iqavat35	Seleção Argentina Camisa I (Home) 24/25	G	389.9	1	/jerseys/placeholder.jpg
391	cmq848iyr00mdlz65k4nrp5xw	cmq848ij9002wlz659yg4uu4y	Liverpool Camisa I (Home) 24/25	P	459.9	1	/jerseys/placeholder.jpg
392	cmq848iyr00mdlz65k4nrp5xw	cmq848ii2001ilz65yyaupzh9	Fluminense Camisa I (Home) 24/25	P	299.9	2	/jerseys/placeholder.jpg
393	cmq848iys00mflz65g1wakerw	cmq848ih4000klz659lkpbiir	Palmeiras Camisa II (Away) 24/25	G	329.9	2	/jerseys/placeholder.jpg
394	cmq848iyu00mhlz65r1qdfa6n	cmq848iha000slz65x7kqdxj9	São Paulo Camisa I (Home) 24/25	M	319.9	1	/jerseys/placeholder.jpg
395	cmq848iyu00mhlz65r1qdfa6n	cmq848ilc005elz6582om42hx	Flamengo Retrô 81 Camisa II (Away) 24/25	M	259.9	1	/jerseys/placeholder.jpg
396	cmq848iyu00mhlz65r1qdfa6n	cmq848iln005olz65hnhu8jjb	Santos Retrô Pelé Camisa I (Home) 24/25	G	269.9	1	/jerseys/placeholder.jpg
397	cmq848iyu00mhlz65r1qdfa6n	cmq848ii3001klz65yorar9lb	Fluminense Camisa II (Away) 24/25	P	299.9	1	/jerseys/placeholder.jpg
398	cmq848iyw00mjlz65i0kx3hp0	cmq848ijz003qlz65dhquij4u	Inter de Milão Camisa II (Away) 24/25	G	449.9	1	/jerseys/placeholder.jpg
399	cmq848iyw00mjlz65i0kx3hp0	cmq848ije0032lz6553k06x48	Bayern de Munique Camisa I (Home) 24/25	M	479.9	2	/jerseys/placeholder.jpg
400	cmq848iyz00mllz65o8jcb496	cmq848il70058lz65kvskyjj0	Seleção México Camisa II (Away) 24/25	M	349.9	1	/jerseys/placeholder.jpg
401	cmq848iyz00mllz65o8jcb496	cmq848ijf0034lz65wj1d3jhk	Bayern de Munique Camisa II (Away) 24/25	M	479.9	1	/jerseys/placeholder.jpg
402	cmq848iyz00mllz65o8jcb496	cmq848iht0018lz65i6s6humm	Vasco Camisa I (Home) 24/25	GG	299.9	1	/jerseys/placeholder.jpg
403	cmq848iyz00mllz65o8jcb496	cmq848ijz003qlz65dhquij4u	Inter de Milão Camisa II (Away) 24/25	G	449.9	2	/jerseys/placeholder.jpg
404	cmq848iz300mnlz65t8ji9dd6	cmq848iit002alz65y173ku0u	Fortaleza Camisa I (Home) 24/25	M	289.9	1	/jerseys/placeholder.jpg
405	cmq848iz300mnlz65t8ji9dd6	cmq848ih4000klz659lkpbiir	Palmeiras Camisa II (Away) 24/25	GG	329.9	1	/jerseys/placeholder.jpg
406	cmq848iz500mplz65qia18yaz	cmq848ikt004ulz651faf9oi1	Seleção Itália Camisa II (Away) 24/25	G	369.9	1	/jerseys/placeholder.jpg
407	cmq848iz500mplz65qia18yaz	cmq848ii5001mlz6549m4ra8a	Fluminense Camisa III (Third) 24/25	M	319.9	1	/jerseys/placeholder.jpg
408	cmq848iz500mplz65qia18yaz	cmq848ilv005ylz65yszzgfgb	Chelsea Camisa I (Home) 24/25	GG	459.9	2	/jerseys/placeholder.jpg
409	cmq848iz500mplz65qia18yaz	cmq848iky004ylz65gaaevnn2	Seleção Inglaterra Camisa II (Away) 24/25	G	369.9	1	/jerseys/placeholder.jpg
410	cmq848iz900mrlz65cxb68ikw	cmq848ilc005elz6582om42hx	Flamengo Retrô 81 Camisa II (Away) 24/25	M	259.9	1	/jerseys/placeholder.jpg
411	cmq848izb00mtlz65uzgx6mqp	cmq848ihz001elz655wdbodk7	Botafogo Camisa I (Home) 24/25	M	299.9	2	/jerseys/placeholder.jpg
412	cmq848izb00mtlz65uzgx6mqp	cmq848ij8002ulz65bg2e9a8o	Manchester City Camisa II (Away) 24/25	M	459.9	1	/jerseys/placeholder.jpg
413	cmq848izb00mtlz65uzgx6mqp	cmq848ihx001clz659v8onw95	Vasco Camisa III (Third) 24/25	G	319.9	2	/jerseys/placeholder.jpg
414	cmq848izb00mtlz65uzgx6mqp	cmq848ilk005mlz65s3sdjsu8	Brasil Retrô 70 Camisa III (Third) 24/25	GG	299.9	1	/jerseys/placeholder.jpg
415	cmq848ize00mvlz65kfw5a0bl	cmq848ihq0016lz65zw3mbwpe	Internacional Camisa III (Third) 24/25	P	329.9	1	/jerseys/placeholder.jpg
416	cmq848izj00mxlz65cbiz0b98	cmq848ikp004olz65mh31wm60	Seleção Espanha Camisa II (Away) 24/25	GG	369.9	1	/jerseys/placeholder.jpg
417	cmq848izj00mxlz65cbiz0b98	cmq848iia001slz65fc01vzde	Atlético-MG Camisa III (Third) 24/25	GG	329.9	1	/jerseys/placeholder.jpg
418	cmq848izj00mxlz65cbiz0b98	cmq848ij0002klz65fxbxd314	Real Madrid Camisa III (Third) 24/25	P	519.9	2	/jerseys/placeholder.jpg
419	cmq848izm00mzlz65zhxaane0	cmq848igs000clz65lnk7697z	Flamengo Camisa I (Home) 24/25	P	349.9	1	/jerseys/placeholder.jpg
420	cmq848izm00mzlz65zhxaane0	cmq848ikg004clz65fx2aw0yf	Seleção França Camisa II (Away) 24/25	GG	379.9	1	/jerseys/placeholder.jpg
421	cmq848izm00mzlz65zhxaane0	cmq848ihe000wlz65o8uu03fy	São Paulo Camisa III (Third) 24/25	GG	339.9	1	/jerseys/placeholder.jpg
422	cmq848izm00mzlz65zhxaane0	cmq848iiz002ilz65pe7qyt2o	Real Madrid Camisa II (Away) 24/25	M	499.9	1	/jerseys/placeholder.jpg
423	cmq848izo00n1lz65sqyxlvyg	cmq848ik4003ylz65rlnlfu47	Seleção Brasileira Camisa III (Third) 24/25	G	409.9	1	/jerseys/placeholder.jpg
424	cmq848izo00n1lz65sqyxlvyg	cmq848ilb005clz65kg0tdzo3	Flamengo Retrô 81 Camisa I (Home) 24/25	P	259.9	1	/jerseys/placeholder.jpg
425	cmq848izq00n3lz65hxa92puc	cmq848il60056lz65m1n86f89	Seleção México Camisa I (Home) 24/25	M	349.9	1	/jerseys/placeholder.jpg
426	cmq848izq00n3lz65hxa92puc	cmq848ihj0012lz655nqbfi4h	Internacional Camisa I (Home) 24/25	G	309.9	1	/jerseys/placeholder.jpg
427	cmq848izs00n5lz65usl7nmkw	cmq848il60056lz65m1n86f89	Seleção México Camisa I (Home) 24/25	GG	349.9	1	/jerseys/placeholder.jpg
428	cmq848izs00n5lz65usl7nmkw	cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	P	459.9	1	/jerseys/placeholder.jpg
429	cmq848izw00n7lz65o956mw4o	cmq848ik90044lz65z6mok81k	Seleção Alemanha Camisa I (Home) 24/25	GG	379.9	2	/jerseys/placeholder.jpg
430	cmq848j0100n9lz65erh5b1sd	cmq848im4006alz65yqqlc42q	Atlético de Madrid Camisa II (Away) 24/25	G	449.9	1	/jerseys/placeholder.jpg
431	cmq848j0100n9lz65erh5b1sd	cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	P	459.9	2	/jerseys/placeholder.jpg
432	cmq848j0500nblz65f0clhqkk	cmq848igs000clz65lnk7697z	Flamengo Camisa I (Home) 24/25	P	349.9	1	/jerseys/placeholder.jpg
433	cmq848j0500nblz65f0clhqkk	cmq848ih0000glz65c18vd6k5	Flamengo Camisa III (Third) 24/25	GG	369.9	1	/jerseys/placeholder.jpg
434	cmq848j0800ndlz65xyzlssco	cmq848ijr003glz651qntef1v	Juventus Camisa II (Away) 24/25	G	459.9	1	/jerseys/placeholder.jpg
435	cmq848j0800ndlz65xyzlssco	cmq848ilq005slz651wha1szo	Borussia Dortmund Camisa I (Home) 24/25	P	449.9	2	/jerseys/placeholder.jpg
436	cmq848j0800ndlz65xyzlssco	cmq848iky004ylz65gaaevnn2	Seleção Inglaterra Camisa II (Away) 24/25	P	369.9	1	/jerseys/placeholder.jpg
437	cmq848j0800ndlz65xyzlssco	cmq848il60056lz65m1n86f89	Seleção México Camisa I (Home) 24/25	GG	349.9	1	/jerseys/placeholder.jpg
438	cmq848j0b00nflz65z510a3sl	cmq848ikk004ilz65atys1fdm	Seleção Portugal Camisa II (Away) 24/25	P	379.9	1	/jerseys/placeholder.jpg
439	cmq848j0e00nhlz654tzscd5t	cmq848ilo005qlz657qbcleae	Santos Retrô Pelé Camisa II (Away) 24/25	GG	269.9	2	/jerseys/placeholder.jpg
440	cmq848j0e00nhlz654tzscd5t	cmq848ijp003elz65vw586mhy	Juventus Camisa I (Home) 24/25	P	459.9	1	/jerseys/placeholder.jpg
441	cmq848j0e00nhlz654tzscd5t	cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	M	459.9	1	/jerseys/placeholder.jpg
442	cmq848j0h00njlz65pk94pm9i	cmq848ilf005ilz65bdq5gcj3	Brasil Retrô 70 Camisa I (Home) 24/25	M	279.9	2	/jerseys/placeholder.jpg
443	cmq848j0k00nllz65g7vbsd1i	cmq848ik70042lz657gy44ygx	Seleção Argentina Camisa II (Away) 24/25	P	389.9	1	/jerseys/placeholder.jpg
444	cmq848j0k00nllz65g7vbsd1i	cmq848ik1003ulz653oni9m29	Seleção Brasileira Camisa I (Home) 24/25	M	389.9	1	/jerseys/placeholder.jpg
445	cmq848j0p00nnlz65rzd22exg	cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	P	459.9	1	/jerseys/placeholder.jpg
446	cmq848j0p00nnlz65rzd22exg	cmq848ik4003ylz65rlnlfu47	Seleção Brasileira Camisa III (Third) 24/25	G	409.9	1	/jerseys/placeholder.jpg
447	cmq848j0u00nplz65xfq36kx7	cmq848ih8000qlz6575344eyf	Corinthians Camisa III (Third) 24/25	GG	339.9	1	/jerseys/placeholder.jpg
448	cmq848j0u00nplz65xfq36kx7	cmq848ikv004wlz65zp7bsxhi	Seleção Inglaterra Camisa I (Home) 24/25	M	369.9	1	/jerseys/placeholder.jpg
449	cmq848j0u00nplz65xfq36kx7	cmq848ihm0014lz65xbhdl0sk	Internacional Camisa II (Away) 24/25	G	309.9	1	/jerseys/placeholder.jpg
450	cmq848j0x00nrlz65k1crmqa1	cmq848ilq005slz651wha1szo	Borussia Dortmund Camisa I (Home) 24/25	GG	449.9	1	/jerseys/placeholder.jpg
451	cmq848j0x00nrlz65k1crmqa1	cmq848ihh0010lz65up1lvi82	Grêmio Camisa II (Away) 24/25	M	309.9	1	/jerseys/placeholder.jpg
452	cmq848j0x00nrlz65k1crmqa1	cmq848ik50040lz65iqavat35	Seleção Argentina Camisa I (Home) 24/25	G	389.9	1	/jerseys/placeholder.jpg
453	cmq848j1100ntlz65ja4z77vv	cmq848iiu002clz65afirolli	Fortaleza Camisa II (Away) 24/25	P	289.9	1	/jerseys/placeholder.jpg
454	cmq848j1100ntlz65ja4z77vv	cmq848ilw0060lz65kz1v9b1j	Chelsea Camisa II (Away) 24/25	GG	459.9	1	/jerseys/placeholder.jpg
455	cmq848j1100ntlz65ja4z77vv	cmq848ilk005mlz65s3sdjsu8	Brasil Retrô 70 Camisa III (Third) 24/25	G	299.9	1	/jerseys/placeholder.jpg
456	cmq848j1100ntlz65ja4z77vv	cmq848im4006alz65yqqlc42q	Atlético de Madrid Camisa II (Away) 24/25	M	449.9	1	/jerseys/placeholder.jpg
457	cmq848j1600nvlz653rvq4785	cmq848iks004slz65ehkzn2hc	Seleção Itália Camisa I (Home) 24/25	M	369.9	1	/jerseys/placeholder.jpg
458	cmq848j1600nvlz653rvq4785	cmq848ii8001qlz65zsn7lsl5	Atlético-MG Camisa II (Away) 24/25	GG	309.9	1	/jerseys/placeholder.jpg
459	cmq848j1b00nxlz65litv653t	cmq848iik0022lz65hx9rzq5u	Santos Camisa III (Third) 24/25	GG	319.9	1	/jerseys/placeholder.jpg
460	cmq848j1e00nzlz657775jh98	cmq848ij3002olz65pe3rcpx3	FC Barcelona Camisa II (Away) 24/25	G	499.9	1	/jerseys/placeholder.jpg
461	cmq848j1e00nzlz657775jh98	cmq848ika0046lz65a6qi9yx5	Seleção Alemanha Camisa II (Away) 24/25	P	379.9	1	/jerseys/placeholder.jpg
462	cmq848j1e00nzlz657775jh98	cmq848ilb005clz65kg0tdzo3	Flamengo Retrô 81 Camisa I (Home) 24/25	P	259.9	1	/jerseys/placeholder.jpg
463	cmq848j1e00nzlz657775jh98	cmq848ih5000mlz650gs0sigx	Corinthians Camisa I (Home) 24/25	G	319.9	1	/jerseys/placeholder.jpg
464	cmq848j1i00o1lz65fy8nklgw	cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	GG	459.9	1	/jerseys/placeholder.jpg
465	cmq848j1l00o3lz651443vkv7	cmq848ilo005qlz657qbcleae	Santos Retrô Pelé Camisa II (Away) 24/25	P	269.9	1	/jerseys/placeholder.jpg
466	cmq848j1l00o3lz651443vkv7	cmq848ikj004glz6503ai64kp	Seleção Portugal Camisa I (Home) 24/25	M	379.9	1	/jerseys/placeholder.jpg
467	cmq848j1l00o3lz651443vkv7	cmq848ii3001klz65yorar9lb	Fluminense Camisa II (Away) 24/25	P	299.9	1	/jerseys/placeholder.jpg
468	cmq848j1l00o3lz651443vkv7	cmq848ihx001clz659v8onw95	Vasco Camisa III (Third) 24/25	P	319.9	1	/jerseys/placeholder.jpg
469	cmq848j1q00o5lz65w1tm6mi8	cmq848ijw003mlz653dgdcmdi	Milan Camisa II (Away) 24/25	P	449.9	1	/jerseys/placeholder.jpg
470	cmq848j1v00o7lz654qdqwx34	cmq848ij0002klz65fxbxd314	Real Madrid Camisa III (Third) 24/25	M	519.9	1	/jerseys/placeholder.jpg
471	cmq848j1v00o7lz654qdqwx34	cmq848ihz001elz655wdbodk7	Botafogo Camisa I (Home) 24/25	GG	299.9	1	/jerseys/placeholder.jpg
472	cmq848j2100o9lz65evrot37m	cmq848iim0024lz653bqj3pmx	Bahia Camisa I (Home) 24/25	GG	289.9	1	/jerseys/placeholder.jpg
473	cmq848j2700oblz657b9c81fs	cmq848ihf000ylz651yn37u7c	Grêmio Camisa I (Home) 24/25	GG	309.9	1	/jerseys/placeholder.jpg
474	cmq848j2700oblz657b9c81fs	cmq848ij0002klz65fxbxd314	Real Madrid Camisa III (Third) 24/25	P	519.9	2	/jerseys/placeholder.jpg
475	cmq848j2c00odlz65q4ikyov7	cmq848im10066lz65y0qob3c4	Arsenal Camisa III (Third) 24/25	M	479.9	2	/jerseys/placeholder.jpg
476	cmq848j2c00odlz65q4ikyov7	cmq848ikn004mlz65b34aur70	Seleção Espanha Camisa I (Home) 24/25	P	369.9	2	/jerseys/placeholder.jpg
477	cmq848j2i00oflz65dmmf51ig	cmq848ilc005elz6582om42hx	Flamengo Retrô 81 Camisa II (Away) 24/25	M	259.9	1	/jerseys/placeholder.jpg
478	cmq848j2i00oflz65dmmf51ig	cmq848ika0046lz65a6qi9yx5	Seleção Alemanha Camisa II (Away) 24/25	G	379.9	2	/jerseys/placeholder.jpg
479	cmq848j2o00ohlz65dk5pu6vt	cmq848iie001wlz65u8ntejt8	Cruzeiro Camisa II (Away) 24/25	M	299.9	1	/jerseys/placeholder.jpg
480	cmq848j2o00ohlz65dk5pu6vt	cmq848ilv005ylz65yszzgfgb	Chelsea Camisa I (Home) 24/25	P	459.9	1	/jerseys/placeholder.jpg
481	cmq848j2o00ohlz65dk5pu6vt	cmq848ilb005clz65kg0tdzo3	Flamengo Retrô 81 Camisa I (Home) 24/25	M	259.9	1	/jerseys/placeholder.jpg
482	cmq848j2o00ohlz65dk5pu6vt	cmq848ike004alz65zfska0qx	Seleção França Camisa I (Home) 24/25	G	379.9	2	/jerseys/placeholder.jpg
483	cmq848j2t00ojlz65cdxxj9pd	cmq848ij6002slz650iblsiyq	Manchester City Camisa I (Home) 24/25	GG	459.9	1	/jerseys/placeholder.jpg
484	cmq848j2x00ollz65crqwveit	cmq848ihc000ulz65um9y1gnx	São Paulo Camisa II (Away) 24/25	P	319.9	1	/jerseys/placeholder.jpg
485	cmq848j2x00ollz65crqwveit	cmq848ijf0034lz65wj1d3jhk	Bayern de Munique Camisa II (Away) 24/25	G	479.9	1	/jerseys/placeholder.jpg
486	cmq848j2x00ollz65crqwveit	cmq848iim0024lz653bqj3pmx	Bahia Camisa I (Home) 24/25	P	289.9	2	/jerseys/placeholder.jpg
487	cmq848j3100onlz65mgevz91o	cmq848iit002alz65y173ku0u	Fortaleza Camisa I (Home) 24/25	G	289.9	1	/jerseys/placeholder.jpg
488	cmq848j3100onlz65mgevz91o	cmq848ikg004clz65fx2aw0yf	Seleção França Camisa II (Away) 24/25	G	379.9	1	/jerseys/placeholder.jpg
489	cmq848j3100onlz65mgevz91o	cmq848ikp004olz65mh31wm60	Seleção Espanha Camisa II (Away) 24/25	M	369.9	1	/jerseys/placeholder.jpg
490	cmq848j3100onlz65mgevz91o	cmq848ikm004klz65hb0e9zxy	Seleção Portugal Camisa III (Third) 24/25	P	399.9	1	/jerseys/placeholder.jpg
491	cmq848j3600oplz65ylbg86j7	cmq848iio0026lz65jq33hxb7	Bahia Camisa II (Away) 24/25	P	289.9	1	/jerseys/placeholder.jpg
492	cmq848j3600oplz65ylbg86j7	cmq848ijp003elz65vw586mhy	Juventus Camisa I (Home) 24/25	G	459.9	1	/jerseys/placeholder.jpg
493	cmq848j3800orlz65i2a3u5e8	cmq848ilk005mlz65s3sdjsu8	Brasil Retrô 70 Camisa III (Third) 24/25	M	299.9	1	/jerseys/placeholder.jpg
494	cmq848j3a00otlz65ww9gkus8	cmq848ijf0034lz65wj1d3jhk	Bayern de Munique Camisa II (Away) 24/25	GG	479.9	1	/jerseys/placeholder.jpg
495	cmq848j3b00ovlz65dp9lxnzk	cmq848iiu002clz65afirolli	Fortaleza Camisa II (Away) 24/25	P	289.9	1	/jerseys/placeholder.jpg
496	cmq848j3b00ovlz65dp9lxnzk	cmq848iic001ulz65hgqi8ctd	Cruzeiro Camisa I (Home) 24/25	G	299.9	1	/jerseys/placeholder.jpg
\.


--
-- Data for Name: Payment; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Payment" (id, "orderId", method, brand, last4, "holderName", amount, status, "paidAt") FROM stdin;
cmq848j3f00oxlz65jqzpmbj1	cmq848it500i9lz65ikq63i80	boleto	Mastercard	1590	Sílvia Batista	304.9	approved	2026-02-22 04:17:00.731
cmq848j3i00ozlz65vmx78ksm	cmq848itc00iblz65livqt9c5	boleto	Visa	3453	Sirineu Santos	324.9	approved	2026-04-19 23:46:59.64
cmq848j3k00p1lz65vkc111j0	cmq848itf00idlz65df7sbixf	credit_card	Visa	0914	Margarida Carvalho	1284.64	approved	2026-01-07 11:25:35.607
cmq848j3l00p3lz6520oqqw8j	cmq848itl00iflz6595hhlyrj	credit_card	Mastercard	4210	Enzo Carvalho	624.8	approved	2026-01-31 02:53:23.428
cmq848j3m00p5lz65iwhqc7h5	cmq848itn00ihlz65x4aoy3ar	pix	Elo	7953	Marcos Batista	1144.7	approved	2026-05-14 18:12:49.711
cmq848j3n00p7lz65vz3j2n9q	cmq848itp00ijlz655ndot5yl	credit_card	Elo	8203	Júlio César Xavier	414.9	approved	2026-02-04 16:01:40.693
cmq848j3p00p9lz65lpfl00ka	cmq848itr00illz65k87uxr4y	boleto	Elo	6716	Liz Braga	1424.7	approved	2026-05-20 22:13:58.626
cmq848j3p00pblz65a9z1uk93	cmq848itt00inlz65yoczfnn0	credit_card	Amex	4794	Srta. Lorena Santos	438.91	approved	2025-12-13 17:28:45.805
cmq848j3q00pdlz65mvpuk9qc	cmq848itw00iplz65ztydciuv	credit_card	Amex	8285	Heloísa Reis	394.9	approved	2026-03-28 09:13:41.402
cmq848j3r00pflz65oowe850g	cmq848iu000irlz65o8902je4	boleto	Amex	3151	Danilo Martins	1404.7	approved	2025-12-25 21:43:27.009
cmq848j3r00phlz652jgn2f90	cmq848iu200itlz65siyd733v	boleto	Mastercard	2160	Benício Martins	964.6999999999999	approved	2026-03-12 01:36:51.76
cmq848j3s00pjlz65iuf88yde	cmq848iu400ivlz65fpjqwil8	pix	Mastercard	7012	Danilo Carvalho	794.8	approved	2026-05-08 06:27:11.779
cmq848j3s00pllz657pppjj1i	cmq848iu600ixlz6548rvqso5	pix	Elo	1966	Margarida Barros	504.9	approved	2026-03-02 05:24:55.169
cmq848j3t00pnlz651jz75t6w	cmq848iu700izlz65ygufdo5l	pix	Elo	2412	Sara Carvalho	824.8	approved	2026-05-06 18:36:54.119
cmq848j3u00pplz65xll3y9bw	cmq848iu900j1lz65ncvvpnsz	pix	Amex	1335	Benício Saraiva	814.8	approved	2026-03-08 10:08:22.355
cmq848j3u00prlz655kr7grpo	cmq848iuc00j3lz65bcrmx0k8	boleto	Mastercard	4310	Ígor Albuquerque	704.8	approved	2026-05-09 16:25:08.193
cmq848j3v00ptlz65ivcxu4uq	cmq848iug00j5lz65pe2jg1ub	credit_card	Elo	9361	Frederico Franco Filho	1104.73	approved	2026-02-18 07:33:51.028
cmq848j3v00pvlz65hwmre6d5	cmq848iui00j7lz655zhjnsmv	credit_card	Elo	7532	Nataniel Macedo	484.9	approved	2026-04-10 22:29:37.348
cmq848j3w00pxlz65jy25b0l6	cmq848iuk00j9lz65oqqcvfyy	boleto	Elo	8032	Ana Júlia Carvalho	1224.7	approved	2025-12-06 21:37:09.677
cmq848j3x00pzlz65w49469o4	cmq848ium00jblz65hskdikov	credit_card	Amex	8160	Mariana Oliveira	627.8199999999999	approved	2026-01-16 23:15:34.906
cmq848j3x00q1lz65t7m9830f	cmq848iun00jdlz652knhe2s9	credit_card	Visa	1782	Eloá Batista	834.8	approved	2025-12-24 09:07:03.66
cmq848j3y00q3lz65digz7pm1	cmq848iup00jflz658euo1qmh	boleto	Visa	3308	Sílvia Moreira	1059.73	approved	2026-01-27 14:40:52.079
cmq848j3y00q5lz65rk1iig85	cmq848iut00jhlz65tlix4m0l	boleto	Amex	5321	Leonardo Melo	1184.7	approved	2026-01-16 12:17:14.715
cmq848j4000q7lz65qu56v68g	cmq848iuy00jjlz65qon3bzh4	boleto	Mastercard	7862	Heloísa Costa	1654.5	rejected	2026-02-22 08:20:34.575
cmq848j4300q9lz65u4zsoueu	cmq848iv300jllz654jv96sfh	credit_card	Visa	9683	Eloá Moreira	1365.64	approved	2025-12-19 19:17:48.921
cmq848j4500qblz65gomw3811	cmq848iv600jnlz65mvzs49qd	pix	Mastercard	7215	Maria Alice Oliveira	2164.5	approved	2026-03-22 02:29:27.766
cmq848j4600qdlz659sot16pr	cmq848iv900jplz65cl1p86ui	boleto	Visa	4433	Maria Júlia Carvalho	324.9	approved	2026-02-15 10:27:49.435
cmq848j4700qflz657td6tm1i	cmq848ive00jrlz65ed1xt7nq	credit_card	Visa	3117	Maitê Moraes	852.8199999999999	approved	2026-04-06 04:10:40.774
cmq848j4900qhlz65foybp49p	cmq848ivh00jtlz65z8gk6d9q	pix	Elo	6310	João Miguel Moraes	1444.6	approved	2025-12-03 00:39:20.804
cmq848j4900qjlz65k82vjp88	cmq848ivl00jvlz65tdudivac	credit_card	Amex	8476	Heitor Melo	438.91	approved	2026-01-21 10:16:34.331
cmq848j4a00qllz65wsucfztp	cmq848ivn00jxlz65rw5hjmft	pix	Mastercard	1254	Daniel Saraiva	854.8	approved	2026-02-14 09:48:56.277
cmq848j4b00qnlz654kks28y0	cmq848ivr00jzlz652l5i52c3	credit_card	Visa	0131	Feliciano Carvalho	814.8	rejected	2025-12-29 11:22:27.706
cmq848j4c00qplz65d5byrcuz	cmq848ivv00k1lz65z3okgg8h	credit_card	Visa	9977	Lorena Braga	1524.6	approved	2026-01-18 00:08:35.843
cmq848j4c00qrlz65d5ccmqk0	cmq848ivy00k3lz653bpabtwa	pix	Mastercard	0906	Janaína Barros	2194.5	approved	2026-03-16 20:08:13.175
cmq848j4d00qtlz65fmr41y48	cmq848iw000k5lz65tmh7mejf	pix	Amex	4991	Dra. Sílvia Batista	854.8	approved	2026-05-22 09:01:43.834
cmq848j4d00qvlz65wluwe6q3	cmq848iw200k7lz659m1u0m3r	boleto	Visa	4203	Srta. Mariana Braga	644.8	approved	2026-02-24 07:02:14.838
cmq848j4e00qxlz65kqfc5uo8	cmq848iw500k9lz65w52cxj6w	credit_card	Visa	7243	Guilherme Barros	344.9	approved	2026-05-18 22:23:03.344
cmq848j4f00qzlz65lxshdt4l	cmq848iw900kblz65l26lo7su	boleto	Mastercard	4151	Melissa Moraes	1564.5	approved	2026-04-26 20:18:18.54
cmq848j4h00r1lz65m1hm9esg	cmq848iwd00kdlz657i68mzlq	pix	Visa	2056	Sr. Ricardo Nogueira	944.8	approved	2025-12-10 08:09:46.323
cmq848j4i00r3lz65veps20ym	cmq848iwf00kflz65cgzsxcve	pix	Elo	6597	Sirineu Barros	1694.5	rejected	2026-04-23 12:47:38.266
cmq848j4j00r5lz657k7x2ftv	cmq848iwi00khlz652fjlgtnc	pix	Elo	5750	Margarida Barros	1524.6	approved	2026-03-20 14:56:01.408
cmq848j4k00r7lz65md8tfrnn	cmq848iwl00kjlz6509btyvv7	pix	Mastercard	7384	Bryan Reis	1074.7	approved	2026-01-18 03:45:52.24
cmq848j4l00r9lz65cl8s6iz8	cmq848iwp00kllz65v0uxycd4	pix	Mastercard	0475	Fabiano Souza	974.6999999999999	approved	2026-02-09 07:11:41.712
cmq848j4m00rblz65c8s2idxf	cmq848iws00knlz65khwmvu79	credit_card	Mastercard	6419	Pablo Macedo	814.8	approved	2026-03-15 22:08:00.951
cmq848j4n00rdlz65944tizls	cmq848iwv00kplz659us0k4lh	boleto	Amex	6594	Isaac Barros	474.9	approved	2026-02-16 11:57:18.959
cmq848j4n00rflz65d12ntedd	cmq848iwx00krlz65q020xvi2	boleto	Elo	8022	Giovanna Moraes	2254.5	approved	2026-02-24 13:12:33.416
cmq848j4o00rhlz65h61wozem	cmq848iwz00ktlz65zq87bmxq	credit_card	Amex	6419	Davi Lucca Saraiva	304.9	approved	2025-12-27 09:39:25.804
cmq848j4o00rjlz65rbzksc76	cmq848ix200kvlz651uwqfyjz	pix	Elo	8757	Ana Clara Barros	944.8	approved	2026-01-06 20:36:44.785
cmq848j4p00rllz65o81w0tsm	cmq848ix500kxlz65z0ufk33v	credit_card	Amex	4881	Fabiano Franco	294.91	approved	2026-04-07 11:38:40.831
cmq848j4q00rnlz651j18o0zt	cmq848ix900kzlz65ldrrbp41	credit_card	Visa	3503	Maria Clara Moraes	944.8	approved	2026-05-17 23:01:47.506
cmq848j4q00rplz652k5zurna	cmq848ixa00l1lz65i43t0gar	boleto	Visa	5133	Sra. Isabela Braga	1428.64	approved	2026-02-22 18:17:57.53
cmq848j4r00rrlz65hghr5uee	cmq848ixd00l3lz65y25tbb0a	credit_card	Mastercard	0710	Pietro Moraes	714.8	approved	2025-12-26 10:46:19.057
cmq848j4s00rtlz65y57kmofi	cmq848ixf00l5lz65ch5ev9bj	boleto	Elo	2203	Arthur Pereira	474.91	approved	2026-02-10 12:19:37.819
cmq848j4t00rvlz65xmgg53ww	cmq848ixg00l7lz65zj8xgv06	boleto	Mastercard	2442	Clara Santos	1494.6	approved	2026-03-16 10:23:19.832
cmq848j4t00rxlz65hc0gy9ch	cmq848ixj00l9lz65ui9tepm5	credit_card	Amex	1591	Washington Carvalho	334.9	approved	2026-01-12 02:42:42.316
cmq848j4u00rzlz65zly28kvy	cmq848ixm00lblz65o729h5wh	pix	Mastercard	3367	Davi Santos	1275.73	approved	2026-01-08 00:02:26.449
cmq848j4v00s1lz65i7oqat5s	cmq848ixp00ldlz650qujxv3w	boleto	Visa	4191	Lorena Carvalho	1114.7	approved	2026-05-27 07:44:25.586
cmq848j4v00s3lz65h85jyri5	cmq848ixr00lflz65xmbep8er	pix	Elo	5049	Théo Batista	429.91	approved	2025-12-01 01:05:54.196
cmq848j4w00s5lz65vwj2r0et	cmq848ixs00lhlz656ujmi0sx	credit_card	Elo	1099	Karla Moraes	504.9	approved	2026-03-18 10:28:51.706
cmq848j4y00s7lz65y3kdi6ky	cmq848ixt00ljlz65588vdngu	boleto	Elo	6098	Miguel Silva	1444.6	approved	2026-05-26 06:48:49.972
cmq848j4z00s9lz65vsmhj0wv	cmq848ixv00lllz65th7ib12k	pix	Mastercard	9224	Vitória Moreira	394.9	approved	2026-05-27 21:43:22.64
cmq848j5100sblz655lmcujof	cmq848ixx00lnlz658amegiyq	boleto	Visa	6400	Sra. Maria Clara Moreira	384.91	approved	2026-01-02 14:55:28.591
cmq848j5100sdlz65hasdutcy	cmq848ixz00lplz65pbhezdr8	credit_card	Amex	2977	Eloá Braga	814.8	approved	2026-02-20 05:08:06.573
cmq848j5200sflz65iy7cvmfk	cmq848iy300lrlz65uylmszcq	boleto	Visa	5580	Murilo Souza	894.8	approved	2026-01-22 04:02:59.132
cmq848j5300shlz65mzel81to	cmq848iy600ltlz65qrfb6duq	boleto	Visa	7542	Danilo Costa	984.8	approved	2026-02-07 05:21:45.909
cmq848j5300sjlz6554mk96j0	cmq848iy800lvlz651yt2k23b	credit_card	Mastercard	8366	Sarah Melo	2154.4	approved	2026-05-31 22:56:43.603
cmq848j5500sllz65c9br8q2j	cmq848iya00lxlz65fbgwz0f4	credit_card	Amex	8381	Cauã Oliveira	324.9	approved	2026-03-26 22:24:51.508
cmq848j5500snlz65hw3nml7r	cmq848iyc00lzlz655oe5e68o	pix	Amex	8174	Ana Clara Macedo	924.8	approved	2026-05-01 17:08:29.739
cmq848j5600splz65j2qkxnl5	cmq848iyd00m1lz65awujeiog	pix	Elo	7568	Srta. Joana Nogueira	634.8	approved	2026-03-04 21:12:48.167
cmq848j5600srlz65eauq74xv	cmq848iyf00m3lz65p466cck6	credit_card	Elo	8495	Samuel Macedo	504.9	approved	2025-12-18 07:00:49.821
cmq848j5700stlz652z3eqotj	cmq848iyj00m5lz650cn7c5qw	boleto	Elo	7133	Víctor Batista Neto	484.9	approved	2026-05-15 12:36:46.553
cmq848j5800svlz65ctkzex3n	cmq848iym00m7lz65eq9vaf7x	pix	Visa	0270	Sr. Davi Lucca Braga	1564.6	rejected	2026-05-17 14:08:23.022
cmq848j5800sxlz65anggggxn	cmq848iyn00m9lz65fak1k4c3	credit_card	Amex	7902	Alessandra Pereira	366.91	rejected	2025-12-23 01:47:03.602
cmq848j5900szlz65iekafnh6	cmq848iyp00mblz65jqmr6mvv	boleto	Visa	9597	Bernardo Albuquerque	1734.55	approved	2026-01-13 02:31:46.396
cmq848j5a00t1lz65t9dihnm7	cmq848iyr00mdlz65k4nrp5xw	credit_card	Amex	8521	Esther Xavier	1084.7	approved	2026-04-12 12:25:24.163
cmq848j5a00t3lz65t5mim1ee	cmq848iys00mflz65g1wakerw	pix	Elo	2934	Dr. Breno Macedo	618.8199999999999	approved	2026-02-09 00:54:36.631
cmq848j5b00t5lz659avg5u0u	cmq848iyu00mhlz65r1qdfa6n	credit_card	Elo	6333	Benjamin Carvalho	1059.64	approved	2026-04-22 12:41:07.018
cmq848j5b00t7lz65ogqf4bj2	cmq848iyw00mjlz65i0kx3hp0	credit_card	Visa	8666	Joaquim Macedo	1434.7	approved	2026-01-26 23:28:44.309
cmq848j5c00t9lz656jfpllxw	cmq848iyz00mllz65o8jcb496	pix	Amex	9359	Marina Barros	2054.5	approved	2026-01-18 09:05:54.643
cmq848j5d00tblz65jbhelmop	cmq848iz300mnlz65t8ji9dd6	credit_card	Amex	7371	João Pedro Oliveira	644.8	rejected	2026-04-18 22:56:01.083
cmq848j5e00tdlz650wn8hd3q	cmq848iz500mplz65qia18yaz	boleto	Mastercard	9166	Isabel Reis	2004.5	approved	2026-02-08 21:18:53.794
cmq848j5f00tflz65st7a43gs	cmq848iz900mrlz65cxb68ikw	pix	Elo	7997	Aline Batista	258.91	approved	2026-05-28 19:35:59.742
cmq848j5g00thlz65fwlldpp0	cmq848izb00mtlz65uzgx6mqp	boleto	Mastercard	1051	Helena Nogueira	1824.46	approved	2026-05-21 07:56:31.354
cmq848j5h00tjlz6507v47rrp	cmq848ize00mvlz65kfw5a0bl	credit_card	Mastercard	1808	Roberta Braga	354.9	approved	2025-12-21 13:12:40.342
cmq848j5h00tllz65ayx6n4t6	cmq848izj00mxlz65cbiz0b98	boleto	Amex	4016	Rafael Santos	1764.6	approved	2026-05-01 15:53:18.917
cmq848j5i00tnlz65goehckkj	cmq848izm00mzlz65zhxaane0	boleto	Mastercard	5244	Théo Albuquerque	1594.6	approved	2026-05-26 18:43:52.064
cmq848j5j00tplz65knj1fpse	cmq848izo00n1lz65sqyxlvyg	credit_card	Amex	6358	Sr. César Macedo	694.8	approved	2026-02-15 12:27:34.584
cmq848j5j00trlz655j1jar53	cmq848izq00n3lz65hxa92puc	boleto	Mastercard	8204	Dra. Melissa Melo	684.8	approved	2026-05-29 13:25:49.885
cmq848j5k00ttlz656d3n0st8	cmq848izs00n5lz65usl7nmkw	credit_card	Visa	0743	Suélen Reis	834.8	approved	2025-12-07 08:16:22.851
cmq848j5k00tvlz65itecs0an	cmq848izw00n7lz65o956mw4o	boleto	Elo	0312	Antônio Franco	784.8	approved	2026-02-06 12:20:56.65
cmq848j5l00txlz6530k2s85i	cmq848j0100n9lz65erh5b1sd	boleto	Visa	1723	Lara Oliveira	1394.7	approved	2026-04-11 00:24:49.372
cmq848j5m00tzlz656snc3h2w	cmq848j0500nblz65f0clhqkk	boleto	Visa	9148	Laura Martins Neto	672.8199999999999	approved	2026-01-28 03:23:16.223
cmq848j5m00u1lz6523bf78v2	cmq848j0800ndlz65xyzlssco	boleto	Amex	9089	Calebe Albuquerque	1896.55	approved	2026-04-07 10:13:28.996
cmq848j5n00u3lz65ud9bcpor	cmq848j0b00nflz65z510a3sl	boleto	Amex	2882	Dra. Vitória Silva	404.9	approved	2026-06-04 05:25:07.509
cmq848j5o00u5lz655j787cx9	cmq848j0e00nhlz654tzscd5t	credit_card	Elo	1352	Morgana Batista Filho	1484.6	approved	2026-05-16 18:34:40.946
cmq848j5p00u7lz65mba71rso	cmq848j0h00njlz65pk94pm9i	pix	Mastercard	8470	Vitória Braga	584.8	approved	2025-12-12 11:38:16.687
cmq848j5p00u9lz65m4w8xbxi	cmq848j0k00nllz65g7vbsd1i	credit_card	Amex	7387	Júlia Batista	804.8	approved	2026-03-30 05:07:18.75
cmq848j5q00ublz65xoctnw07	cmq848j0p00nnlz65rzd22exg	pix	Elo	2368	Júlio César Macedo	894.8	approved	2025-12-06 08:53:13.332
cmq848j5q00udlz650zrmx1vv	cmq848j0u00nplz65xfq36kx7	pix	Visa	5269	Elisa Xavier	1044.7	approved	2026-03-07 17:02:59.845
cmq848j5r00uflz65rcq2wpfi	cmq848j0x00nrlz65k1crmqa1	boleto	Mastercard	2845	Isis Nogueira	1059.73	approved	2026-03-25 06:42:29.592
cmq848j5s00uhlz65p71jvh3f	cmq848j1100ntlz65ja4z77vv	credit_card	Mastercard	7360	Cauã Macedo	1524.6	approved	2026-04-05 18:20:41.458
cmq848j5s00ujlz65nk26bnzs	cmq848j1600nvlz653rvq4785	boleto	Mastercard	1468	Margarida Oliveira	704.8	approved	2025-12-14 14:59:59.91
cmq848j5t00ullz65dbbmvp6e	cmq848j1b00nxlz65litv653t	pix	Mastercard	0882	Dra. Marli Martins	344.9	approved	2026-06-07 02:54:02.21
cmq848j5u00unlz65oc1t8rsc	cmq848j1e00nzlz657775jh98	boleto	Elo	8412	Lucas Pereira	1484.6	approved	2025-12-11 04:51:33.037
cmq848j5v00uplz65gewj3n6v	cmq848j1i00o1lz65fy8nklgw	pix	Amex	8820	Dra. Felícia Oliveira	484.9	approved	2026-04-01 08:28:04.342
cmq848j5w00urlz65en9gibyv	cmq848j1l00o3lz651443vkv7	credit_card	Mastercard	7277	Marli Martins	1294.6	approved	2026-03-13 10:53:28.337
cmq848j5x00utlz65x0f7yroz	cmq848j1q00o5lz65w1tm6mi8	credit_card	Elo	1242	Víctor Oliveira	429.91	approved	2025-12-14 17:44:10.395
cmq848j5y00uvlz650h4iuw4i	cmq848j1v00o7lz654qdqwx34	boleto	Mastercard	9846	Srta. Maitê Pereira	844.8	approved	2026-04-24 20:10:24.792
cmq848j5z00uxlz65d8754n2w	cmq848j2100o9lz65evrot37m	boleto	Elo	3286	Elisa Xavier	314.9	approved	2026-02-15 02:42:53.661
cmq848j6000uzlz65loq7022m	cmq848j2700oblz657b9c81fs	pix	Mastercard	6058	Júlia Martins	1374.7	approved	2026-05-18 09:30:30.946
cmq848j6100v1lz65l42xz75y	cmq848j2c00odlz65q4ikyov7	credit_card	Visa	1715	Sophia Souza	1724.6	approved	2025-12-06 05:59:30.071
cmq848j6100v3lz651tkr20qr	cmq848j2i00oflz65dmmf51ig	pix	Mastercard	6846	Salvador Oliveira Neto	942.7299999999999	approved	2026-05-14 16:56:36.736
cmq848j6200v5lz659ymo6q6b	cmq848j2o00ohlz65dk5pu6vt	pix	Visa	1991	Isabel Carvalho	1804.5	approved	2026-02-15 06:02:38.488
cmq848j6200v7lz656o2d46pj	cmq848j2t00ojlz65cdxxj9pd	boleto	Visa	9230	Marina Nogueira	438.91	approved	2026-05-28 04:26:43.302
cmq848j6300v9lz650c01rzny	cmq848j2x00ollz65crqwveit	pix	Amex	5968	Rafaela Braga Filho	1404.6	approved	2026-05-27 16:20:19.569
cmq848j6400vblz65cf6gnedq	cmq848j3100onlz65mgevz91o	credit_card	Mastercard	1673	Nataniel Saraiva	1320.64	approved	2026-01-20 11:48:12.511
cmq848j6400vdlz653np4o7gd	cmq848j3600oplz65ylbg86j7	pix	Amex	5635	Maria Eduarda Moraes	774.8	approved	2025-12-20 15:03:00.643
cmq848j6500vflz65f9ug70xk	cmq848j3800orlz65i2a3u5e8	boleto	Amex	6701	Heitor Franco	294.91	approved	2026-02-11 11:22:16.804
cmq848j6600vhlz65tcifgw51	cmq848j3a00otlz65ww9gkus8	pix	Mastercard	9378	Isadora Souza	504.9	approved	2026-05-17 00:12:17.725
cmq848j6600vjlz65j8976vw2	cmq848j3b00ovlz65dp9lxnzk	pix	Elo	3903	Dr. Deneval Braga	614.8	approved	2026-02-20 12:06:11.203
\.


--
-- Data for Name: Product; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Product" (id, name, team, description, price, "imageUrl", images, category, "salesCount", active, "createdAt", "brandId", "categoryId") FROM stdin;
cmq848igs000clz65lnk7697z	Flamengo Camisa I (Home) 24/25	Flamengo	Camisa oficial Flamengo temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	349.9	/jerseys/flamengo.jpg	{}	Times Brasileiros	48	t	2026-06-10 13:39:55.901	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848igy000elz65szym5a03	Flamengo Camisa II (Away) 24/25	Flamengo	Camisa oficial Flamengo temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	349.9	/jerseys/flamengo.jpg	{}	Times Brasileiros	4	t	2026-06-10 13:39:55.907	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848ih0000glz65c18vd6k5	Flamengo Camisa III (Third) 24/25	Flamengo	Camisa oficial Flamengo temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/flamengo.jpg	{}	Times Brasileiros	49	t	2026-06-10 13:39:55.909	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848ih2000ilz65lyxr140a	Palmeiras Camisa I (Home) 24/25	Palmeiras	Camisa oficial Palmeiras temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	329.9	/jerseys/palmeiras.jpg	{}	Times Brasileiros	27	t	2026-06-10 13:39:55.91	cmq848igq0008lz657r4exker	cmq848igi0000lz650ssfolol
cmq848ih4000klz659lkpbiir	Palmeiras Camisa II (Away) 24/25	Palmeiras	Camisa oficial Palmeiras temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	329.9	/jerseys/palmeiras.jpg	{}	Times Brasileiros	16	t	2026-06-10 13:39:55.912	cmq848igq0008lz657r4exker	cmq848igi0000lz650ssfolol
cmq848ih5000mlz650gs0sigx	Corinthians Camisa I (Home) 24/25	Corinthians	Camisa oficial Corinthians temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	319.9	/jerseys/corinthians.jpg	{}	Times Brasileiros	31	t	2026-06-10 13:39:55.914	cmq848igo0006lz65r9knigm5	cmq848igi0000lz650ssfolol
cmq848ih7000olz65sykax64r	Corinthians Camisa II (Away) 24/25	Corinthians	Camisa oficial Corinthians temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	319.9	/jerseys/corinthians.jpg	{}	Times Brasileiros	48	t	2026-06-10 13:39:55.915	cmq848igo0006lz65r9knigm5	cmq848igi0000lz650ssfolol
cmq848ih8000qlz6575344eyf	Corinthians Camisa III (Third) 24/25	Corinthians	Camisa oficial Corinthians temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	339.9	/jerseys/corinthians.jpg	{}	Times Brasileiros	35	t	2026-06-10 13:39:55.917	cmq848igo0006lz65r9knigm5	cmq848igi0000lz650ssfolol
cmq848iha000slz65x7kqdxj9	São Paulo Camisa I (Home) 24/25	São Paulo	Camisa oficial São Paulo temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	319.9	/jerseys/sao-paulo.jpg	{}	Times Brasileiros	14	t	2026-06-10 13:39:55.918	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848ihc000ulz65um9y1gnx	São Paulo Camisa II (Away) 24/25	São Paulo	Camisa oficial São Paulo temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	319.9	/jerseys/sao-paulo.jpg	{}	Times Brasileiros	11	t	2026-06-10 13:39:55.92	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848ihe000wlz65o8uu03fy	São Paulo Camisa III (Third) 24/25	São Paulo	Camisa oficial São Paulo temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	339.9	/jerseys/sao-paulo.jpg	{}	Times Brasileiros	31	t	2026-06-10 13:39:55.922	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848ihf000ylz651yn37u7c	Grêmio Camisa I (Home) 24/25	Grêmio	Camisa oficial Grêmio temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	309.9	/jerseys/gremio.jpg	{}	Times Brasileiros	21	t	2026-06-10 13:39:55.924	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848ihh0010lz65up1lvi82	Grêmio Camisa II (Away) 24/25	Grêmio	Camisa oficial Grêmio temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	309.9	/jerseys/gremio.jpg	{}	Times Brasileiros	28	t	2026-06-10 13:39:55.926	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848ihj0012lz655nqbfi4h	Internacional Camisa I (Home) 24/25	Internacional	Camisa oficial Internacional temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	309.9	/jerseys/internacional.jpg	{}	Times Brasileiros	11	t	2026-06-10 13:39:55.927	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848ihm0014lz65xbhdl0sk	Internacional Camisa II (Away) 24/25	Internacional	Camisa oficial Internacional temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	309.9	/jerseys/internacional.jpg	{}	Times Brasileiros	39	t	2026-06-10 13:39:55.93	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848ihq0016lz65zw3mbwpe	Internacional Camisa III (Third) 24/25	Internacional	Camisa oficial Internacional temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	329.9	/jerseys/internacional.jpg	{}	Times Brasileiros	32	t	2026-06-10 13:39:55.934	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848iht0018lz65i6s6humm	Vasco Camisa I (Home) 24/25	Vasco	Camisa oficial Vasco temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/vasco.jpg	{}	Times Brasileiros	33	t	2026-06-10 13:39:55.938	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848ihv001alz657eusus9a	Vasco Camisa II (Away) 24/25	Vasco	Camisa oficial Vasco temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/vasco.jpg	{}	Times Brasileiros	39	t	2026-06-10 13:39:55.94	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848ihx001clz659v8onw95	Vasco Camisa III (Third) 24/25	Vasco	Camisa oficial Vasco temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	319.9	/jerseys/vasco.jpg	{}	Times Brasileiros	22	t	2026-06-10 13:39:55.941	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848ihz001elz655wdbodk7	Botafogo Camisa I (Home) 24/25	Botafogo	Camisa oficial Botafogo temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/botafogo.jpg	{}	Times Brasileiros	26	t	2026-06-10 13:39:55.943	cmq848igq0008lz657r4exker	cmq848igi0000lz650ssfolol
cmq848ii0001glz65zwwuce61	Botafogo Camisa II (Away) 24/25	Botafogo	Camisa oficial Botafogo temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/botafogo.jpg	{}	Times Brasileiros	13	t	2026-06-10 13:39:55.945	cmq848igq0008lz657r4exker	cmq848igi0000lz650ssfolol
cmq848ii2001ilz65yyaupzh9	Fluminense Camisa I (Home) 24/25	Fluminense	Camisa oficial Fluminense temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/fluminense.jpg	{}	Times Brasileiros	33	t	2026-06-10 13:39:55.946	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848ii3001klz65yorar9lb	Fluminense Camisa II (Away) 24/25	Fluminense	Camisa oficial Fluminense temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/fluminense.jpg	{}	Times Brasileiros	28	t	2026-06-10 13:39:55.948	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848ii5001mlz6549m4ra8a	Fluminense Camisa III (Third) 24/25	Fluminense	Camisa oficial Fluminense temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	319.9	/jerseys/fluminense.jpg	{}	Times Brasileiros	13	t	2026-06-10 13:39:55.949	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848ii6001olz65adf9giip	Atlético-MG Camisa I (Home) 24/25	Atlético-MG	Camisa oficial Atlético-MG temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	309.9	/jerseys/atletico-mg.jpg	{}	Times Brasileiros	22	t	2026-06-10 13:39:55.951	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848ii8001qlz65zsn7lsl5	Atlético-MG Camisa II (Away) 24/25	Atlético-MG	Camisa oficial Atlético-MG temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	309.9	/jerseys/atletico-mg.jpg	{}	Times Brasileiros	17	t	2026-06-10 13:39:55.953	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848iia001slz65fc01vzde	Atlético-MG Camisa III (Third) 24/25	Atlético-MG	Camisa oficial Atlético-MG temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	329.9	/jerseys/atletico-mg.jpg	{}	Times Brasileiros	49	t	2026-06-10 13:39:55.955	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848iic001ulz65hgqi8ctd	Cruzeiro Camisa I (Home) 24/25	Cruzeiro	Camisa oficial Cruzeiro temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/cruzeiro.jpg	{}	Times Brasileiros	31	t	2026-06-10 13:39:55.957	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848iie001wlz65u8ntejt8	Cruzeiro Camisa II (Away) 24/25	Cruzeiro	Camisa oficial Cruzeiro temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/cruzeiro.jpg	{}	Times Brasileiros	13	t	2026-06-10 13:39:55.958	cmq848igp0007lz65zh407rd4	cmq848igi0000lz650ssfolol
cmq848iig001ylz65bxct2alm	Santos Camisa I (Home) 24/25	Santos	Camisa oficial Santos temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/santos.jpg	{}	Times Brasileiros	39	t	2026-06-10 13:39:55.96	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848iij0020lz65icy2v5u5	Santos Camisa II (Away) 24/25	Santos	Camisa oficial Santos temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/santos.jpg	{}	Times Brasileiros	33	t	2026-06-10 13:39:55.963	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848iik0022lz65hx9rzq5u	Santos Camisa III (Third) 24/25	Santos	Camisa oficial Santos temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	319.9	/jerseys/santos.jpg	{}	Times Brasileiros	11	t	2026-06-10 13:39:55.965	cmq848igq0009lz655mjc9c85	cmq848igi0000lz650ssfolol
cmq848iim0024lz653bqj3pmx	Bahia Camisa I (Home) 24/25	Bahia	Camisa oficial Bahia temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	289.9	/jerseys/bahia.jpg	{}	Times Brasileiros	13	t	2026-06-10 13:39:55.967	cmq848igq0008lz657r4exker	cmq848igi0000lz650ssfolol
cmq848iio0026lz65jq33hxb7	Bahia Camisa II (Away) 24/25	Bahia	Camisa oficial Bahia temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	289.9	/jerseys/bahia.jpg	{}	Times Brasileiros	47	t	2026-06-10 13:39:55.969	cmq848igq0008lz657r4exker	cmq848igi0000lz650ssfolol
cmq848iir0028lz65h70y18gn	Bahia Camisa III (Third) 24/25	Bahia	Camisa oficial Bahia temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	309.9	/jerseys/bahia.jpg	{}	Times Brasileiros	44	t	2026-06-10 13:39:55.971	cmq848igq0008lz657r4exker	cmq848igi0000lz650ssfolol
cmq848iit002alz65y173ku0u	Fortaleza Camisa I (Home) 24/25	Fortaleza	Camisa oficial Fortaleza temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	289.9	/jerseys/fortaleza.jpg	{}	Times Brasileiros	13	t	2026-06-10 13:39:55.973	cmq848igo0006lz65r9knigm5	cmq848igi0000lz650ssfolol
cmq848iiu002clz65afirolli	Fortaleza Camisa II (Away) 24/25	Fortaleza	Camisa oficial Fortaleza temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	289.9	/jerseys/fortaleza.jpg	{}	Times Brasileiros	18	t	2026-06-10 13:39:55.975	cmq848igo0006lz65r9knigm5	cmq848igi0000lz650ssfolol
cmq848iiw002elz65wl2zq8ty	Fortaleza Camisa III (Third) 24/25	Fortaleza	Camisa oficial Fortaleza temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	309.9	/jerseys/fortaleza.jpg	{}	Times Brasileiros	40	t	2026-06-10 13:39:55.976	cmq848igo0006lz65r9knigm5	cmq848igi0000lz650ssfolol
cmq848iix002glz659tsuziwu	Real Madrid Camisa I (Home) 24/25	Real Madrid	Camisa oficial Real Madrid temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	499.9	/jerseys/real-madrid.jpg	{}	Times Europeus	2	t	2026-06-10 13:39:55.978	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848iiz002ilz65pe7qyt2o	Real Madrid Camisa II (Away) 24/25	Real Madrid	Camisa oficial Real Madrid temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	499.9	/jerseys/real-madrid.jpg	{}	Times Europeus	28	t	2026-06-10 13:39:55.979	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848ij0002klz65fxbxd314	Real Madrid Camisa III (Third) 24/25	Real Madrid	Camisa oficial Real Madrid temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	519.9	/jerseys/real-madrid.jpg	{}	Times Europeus	13	t	2026-06-10 13:39:55.981	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848ij2002mlz65butp1eug	FC Barcelona Camisa I (Home) 24/25	FC Barcelona	Camisa oficial FC Barcelona temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	499.9	/jerseys/fc-barcelona.jpg	{}	Times Europeus	29	t	2026-06-10 13:39:55.982	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ij3002olz65pe3rcpx3	FC Barcelona Camisa II (Away) 24/25	FC Barcelona	Camisa oficial FC Barcelona temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	499.9	/jerseys/fc-barcelona.jpg	{}	Times Europeus	49	t	2026-06-10 13:39:55.984	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ij5002qlz65chlhp8ai	FC Barcelona Camisa III (Third) 24/25	FC Barcelona	Camisa oficial FC Barcelona temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	519.9	/jerseys/fc-barcelona.jpg	{}	Times Europeus	26	t	2026-06-10 13:39:55.985	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ij6002slz650iblsiyq	Manchester City Camisa I (Home) 24/25	Manchester City	Camisa oficial Manchester City temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/manchester-city.jpg	{}	Times Europeus	3	t	2026-06-10 13:39:55.987	cmq848igq0008lz657r4exker	cmq848igk0001lz65ezdcc7ni
cmq848ij8002ulz65bg2e9a8o	Manchester City Camisa II (Away) 24/25	Manchester City	Camisa oficial Manchester City temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/manchester-city.jpg	{}	Times Europeus	46	t	2026-06-10 13:39:55.988	cmq848igq0008lz657r4exker	cmq848igk0001lz65ezdcc7ni
cmq848ij9002wlz659yg4uu4y	Liverpool Camisa I (Home) 24/25	Liverpool	Camisa oficial Liverpool temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/liverpool.jpg	{}	Times Europeus	49	t	2026-06-10 13:39:55.989	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ijb002ylz65ahgqa8zj	Liverpool Camisa II (Away) 24/25	Liverpool	Camisa oficial Liverpool temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/liverpool.jpg	{}	Times Europeus	17	t	2026-06-10 13:39:55.991	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ijc0030lz65k5f1ruxs	Liverpool Camisa III (Third) 24/25	Liverpool	Camisa oficial Liverpool temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	479.9	/jerseys/liverpool.jpg	{}	Times Europeus	29	t	2026-06-10 13:39:55.993	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ije0032lz6553k06x48	Bayern de Munique Camisa I (Home) 24/25	Bayern de Munique	Camisa oficial Bayern de Munique temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	479.9	/jerseys/bayern-de-munique.jpg	{}	Times Europeus	44	t	2026-06-10 13:39:55.994	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848ijf0034lz65wj1d3jhk	Bayern de Munique Camisa II (Away) 24/25	Bayern de Munique	Camisa oficial Bayern de Munique temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	479.9	/jerseys/bayern-de-munique.jpg	{}	Times Europeus	16	t	2026-06-10 13:39:55.995	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848ijh0036lz65wsfy2t1j	Bayern de Munique Camisa III (Third) 24/25	Bayern de Munique	Camisa oficial Bayern de Munique temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	499.9	/jerseys/bayern-de-munique.jpg	{}	Times Europeus	27	t	2026-06-10 13:39:55.997	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848iji0038lz657sbpyxzb	PSG Camisa I (Home) 24/25	PSG	Camisa oficial PSG temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	479.9	/jerseys/psg.jpg	{}	Times Europeus	45	t	2026-06-10 13:39:55.998	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ijm003alz65amc0d44b	PSG Camisa II (Away) 24/25	PSG	Camisa oficial PSG temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	479.9	/jerseys/psg.jpg	{}	Times Europeus	3	t	2026-06-10 13:39:56.002	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ijo003clz65wfuym48q	PSG Camisa III (Third) 24/25	PSG	Camisa oficial PSG temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	499.9	/jerseys/psg.jpg	{}	Times Europeus	3	t	2026-06-10 13:39:56.004	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ijp003elz65vw586mhy	Juventus Camisa I (Home) 24/25	Juventus	Camisa oficial Juventus temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/juventus.jpg	{}	Times Europeus	39	t	2026-06-10 13:39:56.006	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848ijr003glz651qntef1v	Juventus Camisa II (Away) 24/25	Juventus	Camisa oficial Juventus temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/juventus.jpg	{}	Times Europeus	28	t	2026-06-10 13:39:56.007	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848ijs003ilz651vofcqoz	Juventus Camisa III (Third) 24/25	Juventus	Camisa oficial Juventus temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	479.9	/jerseys/juventus.jpg	{}	Times Europeus	27	t	2026-06-10 13:39:56.008	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848iju003klz655h9g7ycn	Milan Camisa I (Home) 24/25	Milan	Camisa oficial Milan temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	449.9	/jerseys/milan.jpg	{}	Times Europeus	3	t	2026-06-10 13:39:56.01	cmq848igq0008lz657r4exker	cmq848igk0001lz65ezdcc7ni
cmq848ijw003mlz653dgdcmdi	Milan Camisa II (Away) 24/25	Milan	Camisa oficial Milan temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	449.9	/jerseys/milan.jpg	{}	Times Europeus	10	t	2026-06-10 13:39:56.012	cmq848igq0008lz657r4exker	cmq848igk0001lz65ezdcc7ni
cmq848ijx003olz659ubwcr00	Inter de Milão Camisa I (Home) 24/25	Inter de Milão	Camisa oficial Inter de Milão temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	449.9	/jerseys/inter-de-milao.jpg	{}	Times Europeus	15	t	2026-06-10 13:39:56.014	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ijz003qlz65dhquij4u	Inter de Milão Camisa II (Away) 24/25	Inter de Milão	Camisa oficial Inter de Milão temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	449.9	/jerseys/inter-de-milao.jpg	{}	Times Europeus	22	t	2026-06-10 13:39:56.015	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ik0003slz65tua1l71k	Inter de Milão Camisa III (Third) 24/25	Inter de Milão	Camisa oficial Inter de Milão temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	469.9	/jerseys/inter-de-milao.jpg	{}	Times Europeus	7	t	2026-06-10 13:39:56.016	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ik1003ulz653oni9m29	Seleção Brasileira Camisa I (Home) 24/25	Seleção Brasileira	Camisa oficial Seleção Brasileira temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	389.9	/jerseys/selecao-brasileira.jpg	{}	Seleções	6	t	2026-06-10 13:39:56.018	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848ik3003wlz6516mr4i90	Seleção Brasileira Camisa II (Away) 24/25	Seleção Brasileira	Camisa oficial Seleção Brasileira temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	389.9	/jerseys/selecao-brasileira.jpg	{}	Seleções	21	t	2026-06-10 13:39:56.019	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848ik4003ylz65rlnlfu47	Seleção Brasileira Camisa III (Third) 24/25	Seleção Brasileira	Camisa oficial Seleção Brasileira temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	409.9	/jerseys/selecao-brasileira.jpg	{}	Seleções	32	t	2026-06-10 13:39:56.021	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848ik50040lz65iqavat35	Seleção Argentina Camisa I (Home) 24/25	Seleção Argentina	Camisa oficial Seleção Argentina temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	389.9	/jerseys/selecao-argentina.jpg	{}	Seleções	33	t	2026-06-10 13:39:56.022	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ik70042lz657gy44ygx	Seleção Argentina Camisa II (Away) 24/25	Seleção Argentina	Camisa oficial Seleção Argentina temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	389.9	/jerseys/selecao-argentina.jpg	{}	Seleções	21	t	2026-06-10 13:39:56.023	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ik90044lz65z6mok81k	Seleção Alemanha Camisa I (Home) 24/25	Seleção Alemanha	Camisa oficial Seleção Alemanha temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	379.9	/jerseys/selecao-alemanha.jpg	{}	Seleções	49	t	2026-06-10 13:39:56.025	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ika0046lz65a6qi9yx5	Seleção Alemanha Camisa II (Away) 24/25	Seleção Alemanha	Camisa oficial Seleção Alemanha temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	379.9	/jerseys/selecao-alemanha.jpg	{}	Seleções	2	t	2026-06-10 13:39:56.027	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ikc0048lz6576k666m5	Seleção Alemanha Camisa III (Third) 24/25	Seleção Alemanha	Camisa oficial Seleção Alemanha temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	399.9	/jerseys/selecao-alemanha.jpg	{}	Seleções	43	t	2026-06-10 13:39:56.029	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ike004alz65zfska0qx	Seleção França Camisa I (Home) 24/25	Seleção França	Camisa oficial Seleção França temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	379.9	/jerseys/selecao-franca.jpg	{}	Seleções	32	t	2026-06-10 13:39:56.03	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848ikg004clz65fx2aw0yf	Seleção França Camisa II (Away) 24/25	Seleção França	Camisa oficial Seleção França temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	379.9	/jerseys/selecao-franca.jpg	{}	Seleções	10	t	2026-06-10 13:39:56.032	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848iki004elz65yy9n3pwk	Seleção França Camisa III (Third) 24/25	Seleção França	Camisa oficial Seleção França temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	399.9	/jerseys/selecao-franca.jpg	{}	Seleções	20	t	2026-06-10 13:39:56.034	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848ikj004glz6503ai64kp	Seleção Portugal Camisa I (Home) 24/25	Seleção Portugal	Camisa oficial Seleção Portugal temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	379.9	/jerseys/selecao-portugal.jpg	{}	Seleções	38	t	2026-06-10 13:39:56.035	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848ikk004ilz65atys1fdm	Seleção Portugal Camisa II (Away) 24/25	Seleção Portugal	Camisa oficial Seleção Portugal temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	379.9	/jerseys/selecao-portugal.jpg	{}	Seleções	42	t	2026-06-10 13:39:56.037	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848ikm004klz65hb0e9zxy	Seleção Portugal Camisa III (Third) 24/25	Seleção Portugal	Camisa oficial Seleção Portugal temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	399.9	/jerseys/selecao-portugal.jpg	{}	Seleções	46	t	2026-06-10 13:39:56.038	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848ikn004mlz65b34aur70	Seleção Espanha Camisa I (Home) 24/25	Seleção Espanha	Camisa oficial Seleção Espanha temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/selecao-espanha.jpg	{}	Seleções	32	t	2026-06-10 13:39:56.04	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ikp004olz65mh31wm60	Seleção Espanha Camisa II (Away) 24/25	Seleção Espanha	Camisa oficial Seleção Espanha temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/selecao-espanha.jpg	{}	Seleções	38	t	2026-06-10 13:39:56.041	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ikq004qlz65201qbcj6	Seleção Espanha Camisa III (Third) 24/25	Seleção Espanha	Camisa oficial Seleção Espanha temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	389.9	/jerseys/selecao-espanha.jpg	{}	Seleções	4	t	2026-06-10 13:39:56.042	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848iks004slz65ehkzn2hc	Seleção Itália Camisa I (Home) 24/25	Seleção Itália	Camisa oficial Seleção Itália temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/selecao-itália.jpg	{}	Seleções	9	t	2026-06-10 13:39:56.044	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ikt004ulz651faf9oi1	Seleção Itália Camisa II (Away) 24/25	Seleção Itália	Camisa oficial Seleção Itália temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/selecao-itália.jpg	{}	Seleções	36	t	2026-06-10 13:39:56.046	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ikv004wlz65zp7bsxhi	Seleção Inglaterra Camisa I (Home) 24/25	Seleção Inglaterra	Camisa oficial Seleção Inglaterra temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/selecao-inglaterra.jpg	{}	Seleções	50	t	2026-06-10 13:39:56.048	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848iky004ylz65gaaevnn2	Seleção Inglaterra Camisa II (Away) 24/25	Seleção Inglaterra	Camisa oficial Seleção Inglaterra temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/selecao-inglaterra.jpg	{}	Seleções	50	t	2026-06-10 13:39:56.05	cmq848igo0006lz65r9knigm5	cmq848igl0002lz65rhw1hugd
cmq848il00050lz65jly7d3ls	Seleção Japão Camisa I (Home) 24/25	Seleção Japão	Camisa oficial Seleção Japão temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	349.9	/jerseys/selecao-japao.jpg	{}	Seleções	22	t	2026-06-10 13:39:56.053	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848il20052lz6542nm8a9p	Seleção Japão Camisa II (Away) 24/25	Seleção Japão	Camisa oficial Seleção Japão temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	349.9	/jerseys/selecao-japao.jpg	{}	Seleções	24	t	2026-06-10 13:39:56.055	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848il40054lz65pt2vtbp1	Seleção Japão Camisa III (Third) 24/25	Seleção Japão	Camisa oficial Seleção Japão temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/selecao-japao.jpg	{}	Seleções	38	t	2026-06-10 13:39:56.057	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848il60056lz65m1n86f89	Seleção México Camisa I (Home) 24/25	Seleção México	Camisa oficial Seleção México temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	349.9	/jerseys/selecao-mexico.jpg	{}	Seleções	12	t	2026-06-10 13:39:56.058	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848il70058lz65kvskyjj0	Seleção México Camisa II (Away) 24/25	Seleção México	Camisa oficial Seleção México temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	349.9	/jerseys/selecao-mexico.jpg	{}	Seleções	45	t	2026-06-10 13:39:56.06	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848il9005alz65fbsfrfd8	Seleção México Camisa III (Third) 24/25	Seleção México	Camisa oficial Seleção México temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	369.9	/jerseys/selecao-mexico.jpg	{}	Seleções	49	t	2026-06-10 13:39:56.061	cmq848igp0007lz65zh407rd4	cmq848igl0002lz65rhw1hugd
cmq848ilb005clz65kg0tdzo3	Flamengo Retrô 81 Camisa I (Home) 24/25	Flamengo Retrô 81	Camisa oficial Flamengo Retrô 81 temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	259.9	/jerseys/flamengo-retrô-81.jpg	{}	Retrô	30	t	2026-06-10 13:39:56.063	cmq848igq0009lz655mjc9c85	cmq848igm0003lz65gh61iz19
cmq848ilc005elz6582om42hx	Flamengo Retrô 81 Camisa II (Away) 24/25	Flamengo Retrô 81	Camisa oficial Flamengo Retrô 81 temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	259.9	/jerseys/flamengo-retrô-81.jpg	{}	Retrô	45	t	2026-06-10 13:39:56.065	cmq848igq0009lz655mjc9c85	cmq848igm0003lz65gh61iz19
cmq848ile005glz654vu28kop	Flamengo Retrô 81 Camisa III (Third) 24/25	Flamengo Retrô 81	Camisa oficial Flamengo Retrô 81 temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	279.9	/jerseys/flamengo-retrô-81.jpg	{}	Retrô	24	t	2026-06-10 13:39:56.066	cmq848igq0009lz655mjc9c85	cmq848igm0003lz65gh61iz19
cmq848ilf005ilz65bdq5gcj3	Brasil Retrô 70 Camisa I (Home) 24/25	Brasil Retrô 70	Camisa oficial Brasil Retrô 70 temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	279.9	/jerseys/brasil-retrô-70.jpg	{}	Retrô	36	t	2026-06-10 13:39:56.068	cmq848igo0006lz65r9knigm5	cmq848igm0003lz65gh61iz19
cmq848ili005klz65un7jjek4	Brasil Retrô 70 Camisa II (Away) 24/25	Brasil Retrô 70	Camisa oficial Brasil Retrô 70 temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	279.9	/jerseys/brasil-retrô-70.jpg	{}	Retrô	9	t	2026-06-10 13:39:56.07	cmq848igo0006lz65r9knigm5	cmq848igm0003lz65gh61iz19
cmq848ilk005mlz65s3sdjsu8	Brasil Retrô 70 Camisa III (Third) 24/25	Brasil Retrô 70	Camisa oficial Brasil Retrô 70 temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	299.9	/jerseys/brasil-retrô-70.jpg	{}	Retrô	32	t	2026-06-10 13:39:56.073	cmq848igo0006lz65r9knigm5	cmq848igm0003lz65gh61iz19
cmq848iln005olz65hnhu8jjb	Santos Retrô Pelé Camisa I (Home) 24/25	Santos Retrô Pelé	Camisa oficial Santos Retrô Pelé temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	269.9	/jerseys/santos-retrô-pele.jpg	{}	Retrô	20	t	2026-06-10 13:39:56.075	cmq848igq0009lz655mjc9c85	cmq848igm0003lz65gh61iz19
cmq848ilo005qlz657qbcleae	Santos Retrô Pelé Camisa II (Away) 24/25	Santos Retrô Pelé	Camisa oficial Santos Retrô Pelé temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	269.9	/jerseys/santos-retrô-pele.jpg	{}	Retrô	20	t	2026-06-10 13:39:56.077	cmq848igq0009lz655mjc9c85	cmq848igm0003lz65gh61iz19
cmq848ilq005slz651wha1szo	Borussia Dortmund Camisa I (Home) 24/25	Borussia Dortmund	Camisa oficial Borussia Dortmund temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	449.9	/jerseys/borussia-dortmund.jpg	{}	Times Europeus	15	t	2026-06-10 13:39:56.078	cmq848igq0008lz657r4exker	cmq848igk0001lz65ezdcc7ni
cmq848ils005ulz653byla82q	Borussia Dortmund Camisa II (Away) 24/25	Borussia Dortmund	Camisa oficial Borussia Dortmund temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	449.9	/jerseys/borussia-dortmund.jpg	{}	Times Europeus	50	t	2026-06-10 13:39:56.08	cmq848igq0008lz657r4exker	cmq848igk0001lz65ezdcc7ni
cmq848ilt005wlz65964p7y2x	Borussia Dortmund Camisa III (Third) 24/25	Borussia Dortmund	Camisa oficial Borussia Dortmund temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	469.9	/jerseys/borussia-dortmund.jpg	{}	Times Europeus	14	t	2026-06-10 13:39:56.082	cmq848igq0008lz657r4exker	cmq848igk0001lz65ezdcc7ni
cmq848ilv005ylz65yszzgfgb	Chelsea Camisa I (Home) 24/25	Chelsea	Camisa oficial Chelsea temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/chelsea.jpg	{}	Times Europeus	34	t	2026-06-10 13:39:56.083	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ilw0060lz65kz1v9b1j	Chelsea Camisa II (Away) 24/25	Chelsea	Camisa oficial Chelsea temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/chelsea.jpg	{}	Times Europeus	27	t	2026-06-10 13:39:56.085	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848ily0062lz65yremo0se	Arsenal Camisa I (Home) 24/25	Arsenal	Camisa oficial Arsenal temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/arsenal.jpg	{}	Times Europeus	44	t	2026-06-10 13:39:56.086	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848im00064lz65vvsub73c	Arsenal Camisa II (Away) 24/25	Arsenal	Camisa oficial Arsenal temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	459.9	/jerseys/arsenal.jpg	{}	Times Europeus	32	t	2026-06-10 13:39:56.088	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848im10066lz65y0qob3c4	Arsenal Camisa III (Third) 24/25	Arsenal	Camisa oficial Arsenal temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	479.9	/jerseys/arsenal.jpg	{}	Times Europeus	19	t	2026-06-10 13:39:56.089	cmq848igp0007lz65zh407rd4	cmq848igk0001lz65ezdcc7ni
cmq848im20068lz65u5y3t9r1	Atlético de Madrid Camisa I (Home) 24/25	Atlético de Madrid	Camisa oficial Atlético de Madrid temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	449.9	/jerseys/atletico-de-madrid.jpg	{}	Times Europeus	27	t	2026-06-10 13:39:56.091	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848im4006alz65yqqlc42q	Atlético de Madrid Camisa II (Away) 24/25	Atlético de Madrid	Camisa oficial Atlético de Madrid temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	449.9	/jerseys/atletico-de-madrid.jpg	{}	Times Europeus	48	t	2026-06-10 13:39:56.092	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
cmq848im5006clz65pzciwfa0	Atlético de Madrid Camisa III (Third) 24/25	Atlético de Madrid	Camisa oficial Atlético de Madrid temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.	469.9	/jerseys/atletico-de-madrid.jpg	{}	Times Europeus	24	t	2026-06-10 13:39:56.094	cmq848igo0006lz65r9knigm5	cmq848igk0001lz65ezdcc7ni
\.


--
-- Data for Name: ProductSize; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."ProductSize" (id, "productId", size, stock, "minStock") FROM stdin;
363	cmq848igs000clz65lnk7697z	G	1	3
368	cmq848igy000elz65szym5a03	GG	1	3
373	cmq848ih2000ilz65lyxr140a	P	1	3
442	cmq848ii0001glz65zwwuce61	M	1	3
455	cmq848ii5001mlz6549m4ra8a	G	1	3
490	cmq848iim0024lz653bqj3pmx	M	1	3
544	cmq848ij8002ulz65bg2e9a8o	GG	1	3
565	cmq848ijh0036lz65wsfy2t1j	P	1	3
569	cmq848iji0038lz657sbpyxzb	P	1	3
576	cmq848ijm003alz65amc0d44b	GG	1	3
609	cmq848ik0003slz65tua1l71k	P	1	3
621	cmq848ik4003ylz65rlnlfu47	P	1	3
623	cmq848ik4003ylz65rlnlfu47	G	1	3
440	cmq848ihz001elz655wdbodk7	GG	2	3
394	cmq848iha000slz65x7kqdxj9	M	2	3
396	cmq848iha000slz65x7kqdxj9	GG	2	3
397	cmq848ihc000ulz65um9y1gnx	P	2	3
437	cmq848ihz001elz655wdbodk7	P	2	3
361	cmq848igs000clz65lnk7697z	P	19	3
362	cmq848igs000clz65lnk7697z	M	16	3
364	cmq848igs000clz65lnk7697z	GG	6	3
365	cmq848igy000elz65szym5a03	P	22	3
366	cmq848igy000elz65szym5a03	M	16	3
367	cmq848igy000elz65szym5a03	G	19	3
369	cmq848ih0000glz65c18vd6k5	P	22	3
370	cmq848ih0000glz65c18vd6k5	M	7	3
371	cmq848ih0000glz65c18vd6k5	G	7	3
372	cmq848ih0000glz65c18vd6k5	GG	7	3
374	cmq848ih2000ilz65lyxr140a	M	9	3
375	cmq848ih2000ilz65lyxr140a	G	17	3
376	cmq848ih2000ilz65lyxr140a	GG	6	3
377	cmq848ih4000klz659lkpbiir	P	11	3
378	cmq848ih4000klz659lkpbiir	M	13	3
379	cmq848ih4000klz659lkpbiir	G	21	3
380	cmq848ih4000klz659lkpbiir	GG	7	3
381	cmq848ih5000mlz650gs0sigx	P	4	3
382	cmq848ih5000mlz650gs0sigx	M	16	3
383	cmq848ih5000mlz650gs0sigx	G	6	3
384	cmq848ih5000mlz650gs0sigx	GG	4	3
385	cmq848ih7000olz65sykax64r	P	25	3
386	cmq848ih7000olz65sykax64r	M	21	3
387	cmq848ih7000olz65sykax64r	G	10	3
388	cmq848ih7000olz65sykax64r	GG	5	3
389	cmq848ih8000qlz6575344eyf	P	13	3
390	cmq848ih8000qlz6575344eyf	M	5	3
391	cmq848ih8000qlz6575344eyf	G	14	3
392	cmq848ih8000qlz6575344eyf	GG	3	3
393	cmq848iha000slz65x7kqdxj9	P	18	3
395	cmq848iha000slz65x7kqdxj9	G	14	3
398	cmq848ihc000ulz65um9y1gnx	M	20	3
399	cmq848ihc000ulz65um9y1gnx	G	24	3
400	cmq848ihc000ulz65um9y1gnx	GG	23	3
401	cmq848ihe000wlz65o8uu03fy	P	24	3
402	cmq848ihe000wlz65o8uu03fy	M	5	3
403	cmq848ihe000wlz65o8uu03fy	G	7	3
404	cmq848ihe000wlz65o8uu03fy	GG	4	3
405	cmq848ihf000ylz651yn37u7c	P	9	3
406	cmq848ihf000ylz651yn37u7c	M	22	3
407	cmq848ihf000ylz651yn37u7c	G	11	3
408	cmq848ihf000ylz651yn37u7c	GG	9	3
409	cmq848ihh0010lz65up1lvi82	P	6	3
410	cmq848ihh0010lz65up1lvi82	M	21	3
411	cmq848ihh0010lz65up1lvi82	G	4	3
412	cmq848ihh0010lz65up1lvi82	GG	25	3
413	cmq848ihj0012lz655nqbfi4h	P	3	3
414	cmq848ihj0012lz655nqbfi4h	M	21	3
415	cmq848ihj0012lz655nqbfi4h	G	19	3
416	cmq848ihj0012lz655nqbfi4h	GG	19	3
417	cmq848ihm0014lz65xbhdl0sk	P	4	3
418	cmq848ihm0014lz65xbhdl0sk	M	11	3
419	cmq848ihm0014lz65xbhdl0sk	G	5	3
420	cmq848ihm0014lz65xbhdl0sk	GG	22	3
421	cmq848ihq0016lz65zw3mbwpe	P	10	3
422	cmq848ihq0016lz65zw3mbwpe	M	4	3
423	cmq848ihq0016lz65zw3mbwpe	G	10	3
424	cmq848ihq0016lz65zw3mbwpe	GG	10	3
425	cmq848iht0018lz65i6s6humm	P	23	3
426	cmq848iht0018lz65i6s6humm	M	13	3
427	cmq848iht0018lz65i6s6humm	G	5	3
428	cmq848iht0018lz65i6s6humm	GG	19	3
429	cmq848ihv001alz657eusus9a	P	15	3
430	cmq848ihv001alz657eusus9a	M	20	3
431	cmq848ihv001alz657eusus9a	G	14	3
432	cmq848ihv001alz657eusus9a	GG	15	3
433	cmq848ihx001clz659v8onw95	P	3	3
434	cmq848ihx001clz659v8onw95	M	5	3
435	cmq848ihx001clz659v8onw95	G	3	3
436	cmq848ihx001clz659v8onw95	GG	17	3
438	cmq848ihz001elz655wdbodk7	M	8	3
439	cmq848ihz001elz655wdbodk7	G	12	3
441	cmq848ii0001glz65zwwuce61	P	4	3
443	cmq848ii0001glz65zwwuce61	G	6	3
444	cmq848ii0001glz65zwwuce61	GG	24	3
445	cmq848ii2001ilz65yyaupzh9	P	23	3
446	cmq848ii2001ilz65yyaupzh9	M	21	3
447	cmq848ii2001ilz65yyaupzh9	G	7	3
448	cmq848ii2001ilz65yyaupzh9	GG	23	3
449	cmq848ii3001klz65yorar9lb	P	21	3
450	cmq848ii3001klz65yorar9lb	M	23	3
451	cmq848ii3001klz65yorar9lb	G	10	3
452	cmq848ii3001klz65yorar9lb	GG	5	3
453	cmq848ii5001mlz6549m4ra8a	P	12	3
454	cmq848ii5001mlz6549m4ra8a	M	21	3
456	cmq848ii5001mlz6549m4ra8a	GG	3	3
457	cmq848ii6001olz65adf9giip	P	8	3
458	cmq848ii6001olz65adf9giip	M	5	3
459	cmq848ii6001olz65adf9giip	G	10	3
460	cmq848ii6001olz65adf9giip	GG	24	3
461	cmq848ii8001qlz65zsn7lsl5	P	14	3
462	cmq848ii8001qlz65zsn7lsl5	M	19	3
463	cmq848ii8001qlz65zsn7lsl5	G	11	3
464	cmq848ii8001qlz65zsn7lsl5	GG	25	3
465	cmq848iia001slz65fc01vzde	P	8	3
466	cmq848iia001slz65fc01vzde	M	14	3
467	cmq848iia001slz65fc01vzde	G	9	3
468	cmq848iia001slz65fc01vzde	GG	9	3
469	cmq848iic001ulz65hgqi8ctd	P	14	3
470	cmq848iic001ulz65hgqi8ctd	M	4	3
471	cmq848iic001ulz65hgqi8ctd	G	9	3
472	cmq848iic001ulz65hgqi8ctd	GG	23	3
473	cmq848iie001wlz65u8ntejt8	P	6	3
474	cmq848iie001wlz65u8ntejt8	M	14	3
475	cmq848iie001wlz65u8ntejt8	G	25	3
476	cmq848iie001wlz65u8ntejt8	GG	8	3
477	cmq848iig001ylz65bxct2alm	P	8	3
478	cmq848iig001ylz65bxct2alm	M	19	3
479	cmq848iig001ylz65bxct2alm	G	11	3
480	cmq848iig001ylz65bxct2alm	GG	17	3
481	cmq848iij0020lz65icy2v5u5	P	15	3
482	cmq848iij0020lz65icy2v5u5	M	5	3
483	cmq848iij0020lz65icy2v5u5	G	22	3
484	cmq848iij0020lz65icy2v5u5	GG	10	3
485	cmq848iik0022lz65hx9rzq5u	P	3	3
486	cmq848iik0022lz65hx9rzq5u	M	16	3
487	cmq848iik0022lz65hx9rzq5u	G	18	3
488	cmq848iik0022lz65hx9rzq5u	GG	3	3
489	cmq848iim0024lz653bqj3pmx	P	17	3
491	cmq848iim0024lz653bqj3pmx	G	18	3
492	cmq848iim0024lz653bqj3pmx	GG	11	3
493	cmq848iio0026lz65jq33hxb7	P	6	3
494	cmq848iio0026lz65jq33hxb7	M	10	3
495	cmq848iio0026lz65jq33hxb7	G	5	3
496	cmq848iio0026lz65jq33hxb7	GG	24	3
497	cmq848iir0028lz65h70y18gn	P	8	3
498	cmq848iir0028lz65h70y18gn	M	18	3
499	cmq848iir0028lz65h70y18gn	G	21	3
500	cmq848iir0028lz65h70y18gn	GG	15	3
501	cmq848iit002alz65y173ku0u	P	5	3
502	cmq848iit002alz65y173ku0u	M	23	3
503	cmq848iit002alz65y173ku0u	G	23	3
504	cmq848iit002alz65y173ku0u	GG	17	3
505	cmq848iiu002clz65afirolli	P	11	3
506	cmq848iiu002clz65afirolli	M	19	3
507	cmq848iiu002clz65afirolli	G	23	3
508	cmq848iiu002clz65afirolli	GG	23	3
509	cmq848iiw002elz65wl2zq8ty	P	17	3
510	cmq848iiw002elz65wl2zq8ty	M	4	3
511	cmq848iiw002elz65wl2zq8ty	G	6	3
513	cmq848iix002glz659tsuziwu	P	5	3
514	cmq848iix002glz659tsuziwu	M	18	3
515	cmq848iix002glz659tsuziwu	G	3	3
516	cmq848iix002glz659tsuziwu	GG	6	3
517	cmq848iiz002ilz65pe7qyt2o	P	18	3
518	cmq848iiz002ilz65pe7qyt2o	M	17	3
519	cmq848iiz002ilz65pe7qyt2o	G	8	3
521	cmq848ij0002klz65fxbxd314	P	10	3
522	cmq848ij0002klz65fxbxd314	M	20	3
523	cmq848ij0002klz65fxbxd314	G	17	3
524	cmq848ij0002klz65fxbxd314	GG	22	3
525	cmq848ij2002mlz65butp1eug	P	5	3
526	cmq848ij2002mlz65butp1eug	M	11	3
527	cmq848ij2002mlz65butp1eug	G	9	3
528	cmq848ij2002mlz65butp1eug	GG	8	3
529	cmq848ij3002olz65pe3rcpx3	P	12	3
530	cmq848ij3002olz65pe3rcpx3	M	23	3
531	cmq848ij3002olz65pe3rcpx3	G	17	3
532	cmq848ij3002olz65pe3rcpx3	GG	21	3
533	cmq848ij5002qlz65chlhp8ai	P	16	3
534	cmq848ij5002qlz65chlhp8ai	M	14	3
535	cmq848ij5002qlz65chlhp8ai	G	7	3
536	cmq848ij5002qlz65chlhp8ai	GG	19	3
537	cmq848ij6002slz650iblsiyq	P	17	3
538	cmq848ij6002slz650iblsiyq	M	7	3
539	cmq848ij6002slz650iblsiyq	G	24	3
540	cmq848ij6002slz650iblsiyq	GG	24	3
541	cmq848ij8002ulz65bg2e9a8o	P	11	3
542	cmq848ij8002ulz65bg2e9a8o	M	3	3
543	cmq848ij8002ulz65bg2e9a8o	G	24	3
545	cmq848ij9002wlz659yg4uu4y	P	22	3
546	cmq848ij9002wlz659yg4uu4y	M	9	3
547	cmq848ij9002wlz659yg4uu4y	G	11	3
548	cmq848ij9002wlz659yg4uu4y	GG	22	3
549	cmq848ijb002ylz65ahgqa8zj	P	6	3
550	cmq848ijb002ylz65ahgqa8zj	M	15	3
551	cmq848ijb002ylz65ahgqa8zj	G	24	3
552	cmq848ijb002ylz65ahgqa8zj	GG	19	3
553	cmq848ijc0030lz65k5f1ruxs	P	5	3
554	cmq848ijc0030lz65k5f1ruxs	M	17	3
555	cmq848ijc0030lz65k5f1ruxs	G	25	3
556	cmq848ijc0030lz65k5f1ruxs	GG	6	3
557	cmq848ije0032lz6553k06x48	P	20	3
558	cmq848ije0032lz6553k06x48	M	19	3
559	cmq848ije0032lz6553k06x48	G	19	3
560	cmq848ije0032lz6553k06x48	GG	11	3
561	cmq848ijf0034lz65wj1d3jhk	P	21	3
562	cmq848ijf0034lz65wj1d3jhk	M	21	3
563	cmq848ijf0034lz65wj1d3jhk	G	22	3
564	cmq848ijf0034lz65wj1d3jhk	GG	24	3
566	cmq848ijh0036lz65wsfy2t1j	M	21	3
567	cmq848ijh0036lz65wsfy2t1j	G	17	3
568	cmq848ijh0036lz65wsfy2t1j	GG	19	3
570	cmq848iji0038lz657sbpyxzb	M	11	3
571	cmq848iji0038lz657sbpyxzb	G	5	3
572	cmq848iji0038lz657sbpyxzb	GG	16	3
573	cmq848ijm003alz65amc0d44b	P	13	3
574	cmq848ijm003alz65amc0d44b	M	15	3
575	cmq848ijm003alz65amc0d44b	G	9	3
577	cmq848ijo003clz65wfuym48q	P	3	3
578	cmq848ijo003clz65wfuym48q	M	21	3
579	cmq848ijo003clz65wfuym48q	G	11	3
580	cmq848ijo003clz65wfuym48q	GG	5	3
581	cmq848ijp003elz65vw586mhy	P	7	3
582	cmq848ijp003elz65vw586mhy	M	17	3
583	cmq848ijp003elz65vw586mhy	G	4	3
584	cmq848ijp003elz65vw586mhy	GG	4	3
585	cmq848ijr003glz651qntef1v	P	15	3
586	cmq848ijr003glz651qntef1v	M	17	3
587	cmq848ijr003glz651qntef1v	G	19	3
588	cmq848ijr003glz651qntef1v	GG	25	3
589	cmq848ijs003ilz651vofcqoz	P	10	3
590	cmq848ijs003ilz651vofcqoz	M	21	3
591	cmq848ijs003ilz651vofcqoz	G	9	3
592	cmq848ijs003ilz651vofcqoz	GG	13	3
512	cmq848iiw002elz65wl2zq8ty	GG	2	3
520	cmq848iiz002ilz65pe7qyt2o	GG	2	3
593	cmq848iju003klz655h9g7ycn	P	25	3
594	cmq848iju003klz655h9g7ycn	M	22	3
595	cmq848iju003klz655h9g7ycn	G	19	3
596	cmq848iju003klz655h9g7ycn	GG	12	3
597	cmq848ijw003mlz653dgdcmdi	P	6	3
598	cmq848ijw003mlz653dgdcmdi	M	8	3
599	cmq848ijw003mlz653dgdcmdi	G	15	3
600	cmq848ijw003mlz653dgdcmdi	GG	19	3
601	cmq848ijx003olz659ubwcr00	P	24	3
602	cmq848ijx003olz659ubwcr00	M	19	3
603	cmq848ijx003olz659ubwcr00	G	15	3
604	cmq848ijx003olz659ubwcr00	GG	17	3
605	cmq848ijz003qlz65dhquij4u	P	8	3
606	cmq848ijz003qlz65dhquij4u	M	11	3
607	cmq848ijz003qlz65dhquij4u	G	20	3
608	cmq848ijz003qlz65dhquij4u	GG	3	3
610	cmq848ik0003slz65tua1l71k	M	3	3
611	cmq848ik0003slz65tua1l71k	G	22	3
612	cmq848ik0003slz65tua1l71k	GG	19	3
613	cmq848ik1003ulz653oni9m29	P	14	3
614	cmq848ik1003ulz653oni9m29	M	13	3
615	cmq848ik1003ulz653oni9m29	G	6	3
616	cmq848ik1003ulz653oni9m29	GG	12	3
617	cmq848ik3003wlz6516mr4i90	P	17	3
618	cmq848ik3003wlz6516mr4i90	M	17	3
619	cmq848ik3003wlz6516mr4i90	G	4	3
620	cmq848ik3003wlz6516mr4i90	GG	11	3
622	cmq848ik4003ylz65rlnlfu47	M	22	3
624	cmq848ik4003ylz65rlnlfu47	GG	6	3
625	cmq848ik50040lz65iqavat35	P	3	3
626	cmq848ik50040lz65iqavat35	M	16	3
628	cmq848ik50040lz65iqavat35	GG	16	3
629	cmq848ik70042lz657gy44ygx	P	17	3
630	cmq848ik70042lz657gy44ygx	M	13	3
631	cmq848ik70042lz657gy44ygx	G	15	3
632	cmq848ik70042lz657gy44ygx	GG	24	3
633	cmq848ik90044lz65z6mok81k	P	23	3
634	cmq848ik90044lz65z6mok81k	M	7	3
635	cmq848ik90044lz65z6mok81k	G	4	3
636	cmq848ik90044lz65z6mok81k	GG	5	3
637	cmq848ika0046lz65a6qi9yx5	P	5	3
638	cmq848ika0046lz65a6qi9yx5	M	18	3
639	cmq848ika0046lz65a6qi9yx5	G	4	3
640	cmq848ika0046lz65a6qi9yx5	GG	10	3
641	cmq848ikc0048lz6576k666m5	P	3	3
642	cmq848ikc0048lz6576k666m5	M	21	3
643	cmq848ikc0048lz6576k666m5	G	9	3
644	cmq848ikc0048lz6576k666m5	GG	5	3
645	cmq848ike004alz65zfska0qx	P	23	3
646	cmq848ike004alz65zfska0qx	M	19	3
647	cmq848ike004alz65zfska0qx	G	21	3
648	cmq848ike004alz65zfska0qx	GG	9	3
649	cmq848ikg004clz65fx2aw0yf	P	20	3
650	cmq848ikg004clz65fx2aw0yf	M	21	3
651	cmq848ikg004clz65fx2aw0yf	G	25	3
652	cmq848ikg004clz65fx2aw0yf	GG	12	3
653	cmq848iki004elz65yy9n3pwk	P	20	3
654	cmq848iki004elz65yy9n3pwk	M	10	3
655	cmq848iki004elz65yy9n3pwk	G	24	3
656	cmq848iki004elz65yy9n3pwk	GG	22	3
657	cmq848ikj004glz6503ai64kp	P	20	3
658	cmq848ikj004glz6503ai64kp	M	5	3
659	cmq848ikj004glz6503ai64kp	G	23	3
660	cmq848ikj004glz6503ai64kp	GG	14	3
661	cmq848ikk004ilz65atys1fdm	P	10	3
662	cmq848ikk004ilz65atys1fdm	M	23	3
663	cmq848ikk004ilz65atys1fdm	G	11	3
664	cmq848ikk004ilz65atys1fdm	GG	3	3
665	cmq848ikm004klz65hb0e9zxy	P	5	3
666	cmq848ikm004klz65hb0e9zxy	M	10	3
667	cmq848ikm004klz65hb0e9zxy	G	24	3
668	cmq848ikm004klz65hb0e9zxy	GG	24	3
669	cmq848ikn004mlz65b34aur70	P	13	3
670	cmq848ikn004mlz65b34aur70	M	9	3
671	cmq848ikn004mlz65b34aur70	G	10	3
672	cmq848ikn004mlz65b34aur70	GG	18	3
673	cmq848ikp004olz65mh31wm60	P	21	3
674	cmq848ikp004olz65mh31wm60	M	21	3
675	cmq848ikp004olz65mh31wm60	G	5	3
676	cmq848ikp004olz65mh31wm60	GG	14	3
678	cmq848ikq004qlz65201qbcj6	M	13	3
679	cmq848ikq004qlz65201qbcj6	G	23	3
680	cmq848ikq004qlz65201qbcj6	GG	11	3
681	cmq848iks004slz65ehkzn2hc	P	20	3
682	cmq848iks004slz65ehkzn2hc	M	17	3
683	cmq848iks004slz65ehkzn2hc	G	5	3
684	cmq848iks004slz65ehkzn2hc	GG	4	3
685	cmq848ikt004ulz651faf9oi1	P	4	3
686	cmq848ikt004ulz651faf9oi1	M	21	3
687	cmq848ikt004ulz651faf9oi1	G	19	3
688	cmq848ikt004ulz651faf9oi1	GG	4	3
689	cmq848ikv004wlz65zp7bsxhi	P	11	3
690	cmq848ikv004wlz65zp7bsxhi	M	11	3
691	cmq848ikv004wlz65zp7bsxhi	G	21	3
692	cmq848ikv004wlz65zp7bsxhi	GG	24	3
693	cmq848iky004ylz65gaaevnn2	P	20	3
694	cmq848iky004ylz65gaaevnn2	M	11	3
695	cmq848iky004ylz65gaaevnn2	G	4	3
696	cmq848iky004ylz65gaaevnn2	GG	20	3
697	cmq848il00050lz65jly7d3ls	P	23	3
698	cmq848il00050lz65jly7d3ls	M	5	3
699	cmq848il00050lz65jly7d3ls	G	14	3
700	cmq848il00050lz65jly7d3ls	GG	3	3
701	cmq848il20052lz6542nm8a9p	P	4	3
702	cmq848il20052lz6542nm8a9p	M	5	3
703	cmq848il20052lz6542nm8a9p	G	5	3
704	cmq848il20052lz6542nm8a9p	GG	17	3
705	cmq848il40054lz65pt2vtbp1	P	16	3
706	cmq848il40054lz65pt2vtbp1	M	25	3
707	cmq848il40054lz65pt2vtbp1	G	11	3
708	cmq848il40054lz65pt2vtbp1	GG	9	3
627	cmq848ik50040lz65iqavat35	G	2	3
677	cmq848ikq004qlz65201qbcj6	P	2	3
709	cmq848il60056lz65m1n86f89	P	25	3
710	cmq848il60056lz65m1n86f89	M	3	3
711	cmq848il60056lz65m1n86f89	G	25	3
712	cmq848il60056lz65m1n86f89	GG	3	3
713	cmq848il70058lz65kvskyjj0	P	15	3
714	cmq848il70058lz65kvskyjj0	M	25	3
715	cmq848il70058lz65kvskyjj0	G	4	3
716	cmq848il70058lz65kvskyjj0	GG	15	3
717	cmq848il9005alz65fbsfrfd8	P	15	3
718	cmq848il9005alz65fbsfrfd8	M	17	3
719	cmq848il9005alz65fbsfrfd8	G	19	3
720	cmq848il9005alz65fbsfrfd8	GG	13	3
721	cmq848ilb005clz65kg0tdzo3	P	23	3
722	cmq848ilb005clz65kg0tdzo3	M	4	3
723	cmq848ilb005clz65kg0tdzo3	G	9	3
724	cmq848ilb005clz65kg0tdzo3	GG	24	3
725	cmq848ilc005elz6582om42hx	P	13	3
726	cmq848ilc005elz6582om42hx	M	17	3
727	cmq848ilc005elz6582om42hx	G	9	3
728	cmq848ilc005elz6582om42hx	GG	7	3
729	cmq848ile005glz654vu28kop	P	11	3
730	cmq848ile005glz654vu28kop	M	16	3
731	cmq848ile005glz654vu28kop	G	4	3
732	cmq848ile005glz654vu28kop	GG	25	3
733	cmq848ilf005ilz65bdq5gcj3	P	15	3
734	cmq848ilf005ilz65bdq5gcj3	M	10	3
736	cmq848ilf005ilz65bdq5gcj3	GG	18	3
737	cmq848ili005klz65un7jjek4	P	23	3
738	cmq848ili005klz65un7jjek4	M	21	3
739	cmq848ili005klz65un7jjek4	G	24	3
740	cmq848ili005klz65un7jjek4	GG	19	3
741	cmq848ilk005mlz65s3sdjsu8	P	12	3
742	cmq848ilk005mlz65s3sdjsu8	M	24	3
743	cmq848ilk005mlz65s3sdjsu8	G	22	3
744	cmq848ilk005mlz65s3sdjsu8	GG	4	3
745	cmq848iln005olz65hnhu8jjb	P	21	3
746	cmq848iln005olz65hnhu8jjb	M	25	3
747	cmq848iln005olz65hnhu8jjb	G	6	3
748	cmq848iln005olz65hnhu8jjb	GG	16	3
749	cmq848ilo005qlz657qbcleae	P	25	3
750	cmq848ilo005qlz657qbcleae	M	22	3
751	cmq848ilo005qlz657qbcleae	G	22	3
752	cmq848ilo005qlz657qbcleae	GG	13	3
753	cmq848ilq005slz651wha1szo	P	4	3
754	cmq848ilq005slz651wha1szo	M	22	3
755	cmq848ilq005slz651wha1szo	G	21	3
756	cmq848ilq005slz651wha1szo	GG	25	3
757	cmq848ils005ulz653byla82q	P	15	3
758	cmq848ils005ulz653byla82q	M	20	3
759	cmq848ils005ulz653byla82q	G	24	3
760	cmq848ils005ulz653byla82q	GG	22	3
761	cmq848ilt005wlz65964p7y2x	P	13	3
762	cmq848ilt005wlz65964p7y2x	M	5	3
763	cmq848ilt005wlz65964p7y2x	G	24	3
764	cmq848ilt005wlz65964p7y2x	GG	16	3
765	cmq848ilv005ylz65yszzgfgb	P	17	3
766	cmq848ilv005ylz65yszzgfgb	M	11	3
767	cmq848ilv005ylz65yszzgfgb	G	5	3
768	cmq848ilv005ylz65yszzgfgb	GG	18	3
769	cmq848ilw0060lz65kz1v9b1j	P	20	3
770	cmq848ilw0060lz65kz1v9b1j	M	14	3
771	cmq848ilw0060lz65kz1v9b1j	G	22	3
772	cmq848ilw0060lz65kz1v9b1j	GG	15	3
773	cmq848ily0062lz65yremo0se	P	12	3
774	cmq848ily0062lz65yremo0se	M	6	3
776	cmq848ily0062lz65yremo0se	GG	20	3
777	cmq848im00064lz65vvsub73c	P	19	3
778	cmq848im00064lz65vvsub73c	M	7	3
779	cmq848im00064lz65vvsub73c	G	6	3
780	cmq848im00064lz65vvsub73c	GG	3	3
781	cmq848im10066lz65y0qob3c4	P	16	3
782	cmq848im10066lz65y0qob3c4	M	12	3
783	cmq848im10066lz65y0qob3c4	G	13	3
784	cmq848im10066lz65y0qob3c4	GG	23	3
785	cmq848im20068lz65u5y3t9r1	P	21	3
786	cmq848im20068lz65u5y3t9r1	M	12	3
787	cmq848im20068lz65u5y3t9r1	G	17	3
788	cmq848im20068lz65u5y3t9r1	GG	22	3
789	cmq848im4006alz65yqqlc42q	P	6	3
790	cmq848im4006alz65yqqlc42q	M	24	3
791	cmq848im4006alz65yqqlc42q	G	14	3
792	cmq848im4006alz65yqqlc42q	GG	8	3
794	cmq848im5006clz65pzciwfa0	M	14	3
795	cmq848im5006clz65pzciwfa0	G	10	3
796	cmq848im5006clz65pzciwfa0	GG	17	3
735	cmq848ilf005ilz65bdq5gcj3	G	1	3
775	cmq848ily0062lz65yremo0se	G	1	3
793	cmq848im5006clz65pzciwfa0	P	2	3
\.


--
-- Data for Name: Review; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Review" (id, "productId", "userId", rating, comment, "createdAt") FROM stdin;
cmq848j6700vllz65wdnc4mj9	cmq848ihc000ulz65um9y1gnx	user_066	2	Nota 10, já é minha terceira compra.	2026-02-13 19:09:48.235
cmq848j6a00vnlz65fs55iz7h	cmq848ijf0034lz65wj1d3jhk	user_037	5	Presente pro meu filho, ele adorou!	2026-05-01 23:45:30.75
cmq848j6c00vplz65nt10egl7	cmq848iio0026lz65jq33hxb7	user_101	4	Entrega antes do prazo, adorei!	2025-12-11 00:11:25.415
cmq848j6e00vrlz65rnq1b8k2	cmq848ii5001mlz6549m4ra8a	user_107	4	Esperava melhor qualidade pelo preço.	2026-03-16 01:24:35.322
cmq848j6g00vtlz65ui7v18ob	cmq848ihf000ylz651yn37u7c	user_104	5	Bom custo-benefício.	2026-05-04 03:28:37.827
cmq848j6i00vvlz65ys90tkiz	cmq848il60056lz65m1n86f89	user_026	5	O tamanho ficou perfeito.	2026-04-24 04:58:41.407
cmq848j6j00vxlz65dm8ynuv8	cmq848ijr003glz651qntef1v	user_011	5	Presente pro meu filho, ele adorou!	2026-03-25 04:54:36.733
cmq848j6k00vzlz65qhybzwjz	cmq848ij6002slz650iblsiyq	user_067	4	Material de boa qualidade, recomendo.	2026-02-25 14:49:28.572
cmq848j6l00w1lz6586pjezgk	cmq848ile005glz654vu28kop	user_115	5	Ótima qualidade, tecido leve e confortável.	2026-05-27 08:52:15.118
cmq848j6m00w3lz6528jxxaxt	cmq848iju003klz655h9g7ycn	user_064	3	Camisa bonita mas demorou pra chegar.	2026-03-02 13:29:54.65
cmq848j6n00w5lz65dtpdlnda	cmq848iki004elz65yy9n3pwk	user_117	5	Muito bonita, igual à original.	2026-01-08 19:26:50.272
cmq848j6n00w7lz65rvnbxwju	cmq848iim0024lz653bqj3pmx	user_093	5	Muito confortável pra usar no dia a dia.	2026-01-02 05:53:35.443
cmq848j6o00w9lz652lrbucov	cmq848ii8001qlz65zsn7lsl5	user_002	5	Nota 10, já é minha terceira compra.	2026-05-24 20:58:39.474
cmq848j6o00wblz6568ffhhff	cmq848ije0032lz6553k06x48	user_106	4	Esperava melhor qualidade pelo preço.	2026-01-16 06:09:01.06
cmq848j6p00wdlz653b1p2xqa	cmq848ilw0060lz65kz1v9b1j	user_007	5	O tamanho ficou perfeito.	2026-02-28 18:25:08.758
cmq848j6p00wflz65hhbdo9zc	cmq848ih0000glz65c18vd6k5	user_059	5	Presente pro meu filho, ele adorou!	2026-04-09 21:48:43.065
cmq848j6q00whlz65wg3scyrg	cmq848ij9002wlz659yg4uu4y	user_028	4	Entrega antes do prazo, adorei!	2026-01-31 22:52:53.366
cmq848j6r00wjlz65qzsbpyj5	cmq848ijm003alz65amc0d44b	user_017	3	Muito bonita, igual à original.	2026-02-19 16:33:24.2
cmq848j6s00wllz65cxrja9qn	cmq848ih2000ilz65lyxr140a	user_003	4	Achei o tecido um pouco fino.	2026-05-10 13:41:21.421
cmq848j6t00wnlz65zicp9ao1	cmq848ije0032lz6553k06x48	user_073	4	Cor vibrante, estampa perfeita.	2025-12-08 16:24:03.853
cmq848j6t00wplz65k6tvjd7o	cmq848im5006clz65pzciwfa0	user_108	5	Muito bonita, igual à original.	2025-12-28 06:42:47.64
cmq848j6u00wrlz65qcc3jhr4	cmq848ikg004clz65fx2aw0yf	user_080	3	A costura poderia ser melhor.	2026-02-24 10:35:05.678
cmq848j6v00wtlz65fnc6l3xr	cmq848ikk004ilz65atys1fdm	user_074	4	Cor vibrante, estampa perfeita.	2026-04-02 13:38:39.668
cmq848j6v00wvlz6559uguo0h	cmq848ikc0048lz6576k666m5	user_067	4	Tecido respirável, ótimo pra jogar.	2026-04-02 03:11:02.4
cmq848j6w00wxlz65roze986b	cmq848ikj004glz6503ai64kp	user_063	4	Material de boa qualidade, recomendo.	2025-12-01 06:28:01.501
cmq848j6x00wzlz65dnm9ros9	cmq848ik3003wlz6516mr4i90	user_068	1	Presente pro meu filho, ele adorou!	2026-02-13 21:14:51.314
cmq848j6x00x1lz65zzyfbg4h	cmq848ih8000qlz6575344eyf	user_025	3	Material de boa qualidade, recomendo.	2026-03-26 16:36:22.199
cmq848j6y00x3lz65yqentda2	cmq848ijh0036lz65wsfy2t1j	user_083	2	Nota 10, já é minha terceira compra.	2026-01-24 03:10:59.956
cmq848j6y00x5lz65af2s0gld	cmq848ilf005ilz65bdq5gcj3	user_108	5	Ótima qualidade, tecido leve e confortável.	2025-12-18 02:20:02.893
cmq848j6z00x7lz65vch7kymk	cmq848im10066lz65y0qob3c4	user_035	4	Presente pro meu filho, ele adorou!	2026-05-18 20:32:43.41
cmq848j6z00x9lz65a4xg4x60	cmq848iir0028lz65h70y18gn	user_055	2	Produto exatamente como na foto.	2026-05-10 07:07:40.051
cmq848j7000xblz65yebes63p	cmq848il40054lz65pt2vtbp1	user_062	5	Esperava melhor qualidade pelo preço.	2026-06-05 22:20:14.67
cmq848j7100xdlz653mylaq5s	cmq848il40054lz65pt2vtbp1	user_035	4	Ótima qualidade, tecido leve e confortável.	2026-04-24 23:22:06.435
cmq848j7100xflz65pwr0axr7	cmq848ik90044lz65z6mok81k	user_021	5	Muito confortável pra usar no dia a dia.	2026-01-25 10:15:39.332
cmq848j7200xhlz65jc4ys65i	cmq848ihm0014lz65xbhdl0sk	user_028	2	Tecido respirável, ótimo pra jogar.	2026-04-20 21:58:25.149
cmq848j7200xjlz65gkuj6wvs	cmq848ijh0036lz65wsfy2t1j	user_060	5	Esperava melhor qualidade pelo preço.	2026-01-16 21:56:21.183
cmq848j7300xllz65vuoawwgq	cmq848il40054lz65pt2vtbp1	user_118	4	O tamanho ficou perfeito.	2026-04-29 05:06:45.042
cmq848j7400xnlz65p0k3efi9	cmq848ii0001glz65zwwuce61	user_015	5	Esperava melhor qualidade pelo preço.	2026-04-29 12:58:42.032
cmq848j7500xplz65xjzpgl52	cmq848ihc000ulz65um9y1gnx	user_038	4	Tecido respirável, ótimo pra jogar.	2026-01-12 02:47:13.648
cmq848j7500xrlz65cjkw10lt	cmq848ily0062lz65yremo0se	user_027	1	Camisa linda, já quero a do próximo ano.	2026-05-03 10:55:40.02
cmq848j7600xtlz65kqcy5g3f	cmq848ii5001mlz6549m4ra8a	user_023	5	Camisa bonita mas demorou pra chegar.	2026-05-31 17:45:59.529
cmq848j7600xvlz65yl7duvdy	cmq848ikp004olz65mh31wm60	user_095	5	Muito confortável pra usar no dia a dia.	2026-05-07 07:05:20.15
cmq848j7700xxlz65jp1yj1p8	cmq848ili005klz65un7jjek4	user_020	5	Chegou rápido, produto excelente!	2026-04-04 19:06:34.984
cmq848j7900xzlz65xgspx5i6	cmq848ihe000wlz65o8uu03fy	user_079	5	Camisa linda, já quero a do próximo ano.	2026-04-08 21:37:32.166
cmq848j7a00y1lz651jj7v18p	cmq848ii5001mlz6549m4ra8a	user_088	5	Achei o tecido um pouco fino.	2026-01-17 06:58:35.891
cmq848j7c00y3lz65jgsnvuv3	cmq848ii2001ilz65yyaupzh9	user_029	4	Camisa bonita mas demorou pra chegar.	2026-05-05 20:46:23.767
cmq848j7d00y5lz65znafxf0n	cmq848ijf0034lz65wj1d3jhk	user_023	5	Cor vibrante, estampa perfeita.	2025-12-11 14:37:20.233
cmq848j7d00y7lz65osjl82pf	cmq848ihc000ulz65um9y1gnx	user_059	4	A costura poderia ser melhor.	2026-01-06 05:40:14.425
cmq848j7e00y9lz65j7dlf7jg	cmq848il70058lz65kvskyjj0	user_069	3	Produto exatamente como na foto.	2026-05-17 01:42:53.343
cmq848j7e00yblz65v2hp5mcy	cmq848ij6002slz650iblsiyq	user_113	4	A costura poderia ser melhor.	2026-04-12 10:57:27.186
cmq848j7f00ydlz65io8dq8ki	cmq848igy000elz65szym5a03	user_120	5	Achei o tecido um pouco fino.	2026-01-19 20:09:36.996
cmq848j7f00yflz6596yk1wzw	cmq848ikn004mlz65b34aur70	user_027	5	Tecido respirável, ótimo pra jogar.	2026-04-11 18:01:18.623
cmq848j7g00yhlz653lgdqx6p	cmq848iic001ulz65hgqi8ctd	user_031	4	A costura poderia ser melhor.	2026-05-16 12:46:27.825
cmq848j7h00yjlz658342ftnh	cmq848im10066lz65y0qob3c4	user_103	4	Muito confortável pra usar no dia a dia.	2026-05-03 14:49:13.894
cmq848j7h00yllz655k9nsxlj	cmq848igy000elz65szym5a03	user_108	1	Cor vibrante, estampa perfeita.	2026-05-01 15:42:51.957
cmq848j7i00ynlz65fafcffr8	cmq848ij5002qlz65chlhp8ai	user_016	5	Achei o tecido um pouco fino.	2025-12-24 10:02:44.257
cmq848j7i00yplz65oodlsoii	cmq848igy000elz65szym5a03	user_097	5	O tamanho ficou perfeito.	2026-03-22 22:01:03.249
cmq848j7j00yrlz65vh5926j2	cmq848iie001wlz65u8ntejt8	user_031	4	Comprei pro meu marido e ele amou.	2025-12-24 01:08:58.03
cmq848j7j00ytlz65c8hfufo0	cmq848iia001slz65fc01vzde	user_022	1	Presente pro meu filho, ele adorou!	2026-03-24 19:23:41.328
cmq848j7k00yvlz65m3ogxft1	cmq848ijm003alz65amc0d44b	user_029	5	Ótima qualidade, tecido leve e confortável.	2026-02-28 01:25:29.576
cmq848j7k00yxlz65n0tc0iv0	cmq848ihm0014lz65xbhdl0sk	user_048	4	Camisa linda, já quero a do próximo ano.	2026-02-14 04:08:58.217
cmq848j7l00yzlz65e5xq2krk	cmq848im00064lz65vvsub73c	user_075	3	Cor vibrante, estampa perfeita.	2026-04-20 02:57:07.377
cmq848j7m00z1lz65o02qoj1w	cmq848ijp003elz65vw586mhy	user_016	5	O tamanho ficou perfeito.	2026-02-19 23:50:27.357
cmq848j7m00z3lz65jhf5venl	cmq848ikm004klz65hb0e9zxy	user_016	4	Bom custo-benefício.	2025-12-28 19:28:27.409
cmq848j7n00z5lz65bt6kmbjw	cmq848ik1003ulz653oni9m29	user_017	1	Chegou rápido, produto excelente!	2026-01-24 06:56:07.131
cmq848j7n00z7lz65gu97eq45	cmq848ih8000qlz6575344eyf	user_105	2	Bom custo-benefício.	2026-02-16 13:41:47.361
cmq848j7o00z9lz65hebd3yz7	cmq848iim0024lz653bqj3pmx	user_038	5	Entrega antes do prazo, adorei!	2026-04-17 12:30:22.499
cmq848j7p00zblz6501ay75xp	cmq848il60056lz65m1n86f89	user_081	5	Excelente acabamento, vale cada centavo.	2026-02-26 09:54:07.379
cmq848j7r00zdlz65gqgojl4g	cmq848iio0026lz65jq33hxb7	user_094	4	Entrega antes do prazo, adorei!	2026-02-15 09:48:22.217
cmq848j7s00zflz655o249ydi	cmq848ijr003glz651qntef1v	user_008	5	Comprei pro meu marido e ele amou.	2026-05-30 16:42:36.493
cmq848j7t00zhlz65a43ity8x	cmq848ijf0034lz65wj1d3jhk	user_059	4	Muito bonita, igual à original.	2026-01-18 03:59:17.597
cmq848j7t00zjlz654zd2x92p	cmq848iki004elz65yy9n3pwk	user_111	5	Material de boa qualidade, recomendo.	2026-04-09 17:44:16.559
cmq848j7u00zllz65ypllho7n	cmq848ilc005elz6582om42hx	user_092	5	Muito confortável pra usar no dia a dia.	2026-03-16 01:26:16.205
cmq848j7u00znlz65brgw5zgi	cmq848ik4003ylz65rlnlfu47	user_084	5	Camisa linda, já quero a do próximo ano.	2025-12-24 08:18:45.519
cmq848j7v00zplz65dcy2gbgz	cmq848il70058lz65kvskyjj0	user_031	4	Produto exatamente como na foto.	2026-03-08 23:45:25.268
cmq848j7w00zrlz652nynk3cj	cmq848ilt005wlz65964p7y2x	user_046	5	Entrega antes do prazo, adorei!	2026-01-13 20:31:44.761
cmq848j7x00ztlz65cn3gbu2g	cmq848ihq0016lz65zw3mbwpe	user_102	4	Entrega antes do prazo, adorei!	2026-02-28 23:20:26.843
cmq848j7x00zvlz65tu690n0h	cmq848il60056lz65m1n86f89	user_090	3	Muito confortável pra usar no dia a dia.	2026-02-23 21:33:50.728
cmq848j7y00zxlz65anznrymj	cmq848ih5000mlz650gs0sigx	user_021	5	Muito bonita, igual à original.	2026-03-17 00:14:46.539
cmq848j7z00zzlz65p9ki7syw	cmq848ih4000klz659lkpbiir	user_023	5	Produto exatamente como na foto.	2026-03-23 09:00:42.075
cmq848j7z0101lz65favu5l14	cmq848ilo005qlz657qbcleae	user_043	5	Camisa linda, já quero a do próximo ano.	2026-03-28 02:17:26.029
cmq848j800103lz65238gwvkr	cmq848ikj004glz6503ai64kp	user_023	3	Nota 10, já é minha terceira compra.	2026-05-13 17:02:40.864
cmq848j800105lz65vupnc6pv	cmq848iij0020lz65icy2v5u5	user_019	5	Material de boa qualidade, recomendo.	2026-01-15 08:36:12.176
cmq848j810107lz65vqscdjev	cmq848iha000slz65x7kqdxj9	user_111	4	Bom custo-benefício.	2026-05-20 18:02:25.172
cmq848j810109lz6585830j9u	cmq848ikv004wlz65zp7bsxhi	user_120	1	A costura poderia ser melhor.	2026-06-02 00:12:14.555
cmq848j82010blz659q5lnqy7	cmq848iha000slz65x7kqdxj9	user_085	4	Excelente acabamento, vale cada centavo.	2026-02-05 15:16:35.051
cmq848j83010dlz658nihgu77	cmq848ik0003slz65tua1l71k	user_033	2	Ótima qualidade, tecido leve e confortável.	2026-04-26 03:41:39.438
cmq848j83010flz65hiwjz4ho	cmq848im10066lz65y0qob3c4	user_087	2	A costura poderia ser melhor.	2026-03-09 21:03:50.281
cmq848j84010hlz65ocrbtfyy	cmq848ijw003mlz653dgdcmdi	user_025	3	Entrega antes do prazo, adorei!	2026-04-30 01:05:12.343
cmq848j84010jlz65oo8jprbt	cmq848ik4003ylz65rlnlfu47	user_024	5	Ótima qualidade, tecido leve e confortável.	2026-01-08 01:00:26.882
cmq848j86010llz653afn61cc	cmq848ilc005elz6582om42hx	user_014	5	Achei o tecido um pouco fino.	2026-06-01 09:18:38.763
cmq848j88010nlz65u43su0zn	cmq848igy000elz65szym5a03	user_046	5	Muito bonita, igual à original.	2025-12-20 12:48:25.349
cmq848j8a010plz65lrw0w47h	cmq848ik3003wlz6516mr4i90	user_010	5	Presente pro meu filho, ele adorou!	2026-05-13 18:48:02.828
cmq848j8b010rlz65gc1yaa4d	cmq848ils005ulz653byla82q	user_051	4	Presente pro meu filho, ele adorou!	2026-04-22 13:46:24.627
cmq848j8c010tlz65ji1qt5tb	cmq848ihc000ulz65um9y1gnx	user_009	4	Cor vibrante, estampa perfeita.	2026-04-30 04:17:36.75
cmq848j8e010vlz65bmhex1tx	cmq848ij3002olz65pe3rcpx3	user_110	4	Bom custo-benefício.	2026-06-05 12:08:40.524
cmq848j8f010xlz6507253g4b	cmq848ils005ulz653byla82q	user_100	5	A costura poderia ser melhor.	2026-01-20 10:33:28.461
cmq848j8g010zlz65irs9y1by	cmq848ilw0060lz65kz1v9b1j	user_026	5	Camisa linda, já quero a do próximo ano.	2025-12-29 08:38:03.301
cmq848j8h0111lz65ji1aahx7	cmq848iij0020lz65icy2v5u5	user_099	5	Material de boa qualidade, recomendo.	2026-03-22 05:56:38.521
cmq848j8h0113lz659yuqvkcu	cmq848ike004alz65zfska0qx	user_042	5	Chegou rápido, produto excelente!	2025-12-19 22:27:17.483
cmq848j8i0115lz65hyz5zpmt	cmq848il70058lz65kvskyjj0	user_051	2	Material de boa qualidade, recomendo.	2026-03-20 03:07:33.393
cmq848j8i0117lz65bo3pfvr6	cmq848iik0022lz65hx9rzq5u	user_093	4	Bom custo-benefício.	2025-12-26 15:01:45.478
cmq848j8j0119lz65q4k9ftby	cmq848iht0018lz65i6s6humm	user_004	4	Chegou rápido, produto excelente!	2026-01-06 01:00:55.525
cmq848j8j011blz65sby9spa7	cmq848iha000slz65x7kqdxj9	user_041	5	Muito confortável pra usar no dia a dia.	2025-12-04 16:00:14.554
cmq848j8k011dlz6564un5ilu	cmq848ij2002mlz65butp1eug	user_079	4	Esperava melhor qualidade pelo preço.	2026-01-12 11:09:15.551
cmq848j8k011flz65vv9a2xbs	cmq848ijm003alz65amc0d44b	user_102	3	Nota 10, já é minha terceira compra.	2026-06-06 02:09:58.054
cmq848j8l011hlz65luh1lfkk	cmq848im10066lz65y0qob3c4	user_093	4	Cor vibrante, estampa perfeita.	2026-04-23 12:52:09.734
cmq848j8m011jlz65lpyg0ez0	cmq848im10066lz65y0qob3c4	user_106	5	A costura poderia ser melhor.	2026-01-10 00:32:38.13
cmq848j8n011llz65q3tdhndw	cmq848ihz001elz655wdbodk7	user_066	5	Muito confortável pra usar no dia a dia.	2025-12-28 18:10:24.927
cmq848j8p011nlz651ht9n9z1	cmq848ik3003wlz6516mr4i90	user_076	5	Camisa bonita mas demorou pra chegar.	2026-03-17 23:11:44.378
cmq848j8q011plz65kkn62ar8	cmq848il60056lz65m1n86f89	user_023	1	Material de boa qualidade, recomendo.	2026-01-05 12:19:06.814
cmq848j8r011rlz65in1gkjgb	cmq848ikt004ulz651faf9oi1	user_055	5	Ótima qualidade, tecido leve e confortável.	2026-03-13 19:57:57.83
cmq848j8s011tlz65fv4hk0er	cmq848ij3002olz65pe3rcpx3	user_115	4	Camisa linda, já quero a do próximo ano.	2026-04-11 23:24:38.553
cmq848j8t011vlz65t7u2bni7	cmq848ijz003qlz65dhquij4u	user_087	1	Comprei pro meu marido e ele amou.	2026-05-20 01:20:57.651
cmq848j8u011xlz65cmxjjscc	cmq848iks004slz65ehkzn2hc	user_084	5	Camisa bonita mas demorou pra chegar.	2026-04-28 18:24:36.008
cmq848j8v011zlz65py19wpat	cmq848ijz003qlz65dhquij4u	user_036	5	Produto exatamente como na foto.	2025-12-21 23:53:10.181
cmq848j8w0121lz65na5kd09q	cmq848ik4003ylz65rlnlfu47	user_100	5	Bom custo-benefício.	2026-01-23 16:11:40.905
cmq848j8w0123lz65p5hf7ibm	cmq848iix002glz659tsuziwu	user_039	5	Camisa linda, já quero a do próximo ano.	2025-12-06 23:47:52.455
cmq848j8x0125lz65y1y3b2j0	cmq848ij0002klz65fxbxd314	user_080	4	Presente pro meu filho, ele adorou!	2026-04-08 00:18:10.609
cmq848j8x0127lz651zeeze5o	cmq848ikk004ilz65atys1fdm	user_088	5	Comprei pro meu marido e ele amou.	2026-01-23 04:44:35.612
cmq848j8y0129lz65otzdrvsa	cmq848ij8002ulz65bg2e9a8o	user_004	4	Cor vibrante, estampa perfeita.	2026-04-13 21:59:53.499
cmq848j8z012blz656ix6xooh	cmq848iir0028lz65h70y18gn	user_038	5	Comprei pro meu marido e ele amou.	2026-03-18 21:17:13.116
cmq848j8z012dlz654wya9cvq	cmq848ikm004klz65hb0e9zxy	user_042	4	Cor vibrante, estampa perfeita.	2026-03-08 03:38:23.709
cmq848j90012flz65mit6b7u0	cmq848ike004alz65zfska0qx	user_077	5	Muito bonita, igual à original.	2025-12-30 18:15:06.718
cmq848j90012hlz65woquwv5g	cmq848ilk005mlz65s3sdjsu8	user_077	4	O tamanho ficou perfeito.	2026-04-23 18:06:26.612
cmq848j91012jlz651zwjsqg2	cmq848ilk005mlz65s3sdjsu8	user_100	4	Entrega antes do prazo, adorei!	2025-12-03 22:17:31.957
cmq848j91012llz65fc0el8jd	cmq848ihe000wlz65o8uu03fy	user_013	3	Chegou rápido, produto excelente!	2026-03-05 07:25:17.538
cmq848j93012nlz65i2oehl99	cmq848iio0026lz65jq33hxb7	user_057	2	O tamanho ficou perfeito.	2026-02-05 23:13:49.069
cmq848j96012plz65j7ca2czm	cmq848ih2000ilz65lyxr140a	user_093	4	Produto exatamente como na foto.	2026-05-27 03:08:28.843
cmq848j99012rlz65bewq34nh	cmq848iir0028lz65h70y18gn	user_106	4	Chegou rápido, produto excelente!	2026-01-18 23:53:13.978
cmq848j9b012tlz659vla19bl	cmq848iir0028lz65h70y18gn	user_012	2	Camisa bonita mas demorou pra chegar.	2026-03-17 18:15:19.259
cmq848j9c012vlz65faxo8k8e	cmq848ijf0034lz65wj1d3jhk	user_053	1	Achei o tecido um pouco fino.	2026-03-30 04:35:58.492
cmq848j9d012xlz65jl2cw48i	cmq848ih7000olz65sykax64r	user_051	4	Produto exatamente como na foto.	2025-12-19 18:18:48.733
cmq848j9e012zlz65ln7s794u	cmq848iht0018lz65i6s6humm	user_009	3	Tecido respirável, ótimo pra jogar.	2026-03-18 08:28:51.694
cmq848j9f0131lz65wubffbwb	cmq848iln005olz65hnhu8jjb	user_057	3	Produto exatamente como na foto.	2026-05-04 12:28:33.939
cmq848j9f0133lz65odzwp3xf	cmq848ije0032lz6553k06x48	user_078	2	Muito confortável pra usar no dia a dia.	2025-12-05 12:33:20.006
cmq848j9i0135lz65lps3mwjp	cmq848im00064lz65vvsub73c	user_007	5	Entrega antes do prazo, adorei!	2026-02-12 20:54:20.673
cmq848j9l0137lz65xy1txp8s	cmq848iha000slz65x7kqdxj9	user_015	5	Material de boa qualidade, recomendo.	2026-03-03 19:38:37.298
cmq848j9o0139lz65rv931gyg	cmq848im4006alz65yqqlc42q	user_085	4	Bom custo-benefício.	2026-03-10 03:28:46.554
cmq848j9q013blz65svtpi6m3	cmq848ijr003glz651qntef1v	user_065	5	Ótima qualidade, tecido leve e confortável.	2025-12-19 13:21:30.278
cmq848j9r013dlz656qouut0y	cmq848ikm004klz65hb0e9zxy	user_013	5	Entrega antes do prazo, adorei!	2026-05-26 10:26:41.507
cmq848j9s013flz6511lqexrx	cmq848ilw0060lz65kz1v9b1j	user_118	5	Bom custo-benefício.	2026-01-03 08:04:28.79
cmq848j9s013hlz657iu2o20r	cmq848iln005olz65hnhu8jjb	user_097	2	Nota 10, já é minha terceira compra.	2026-04-24 03:33:10.491
cmq848j9t013jlz65nmaxe4av	cmq848ih4000klz659lkpbiir	user_012	3	Nota 10, já é minha terceira compra.	2026-06-08 03:42:16.73
cmq848j9t013llz651mkbyjh6	cmq848ilf005ilz65bdq5gcj3	user_012	4	Produto exatamente como na foto.	2026-05-05 06:06:01.464
cmq848j9u013nlz65sufxis88	cmq848iim0024lz653bqj3pmx	user_110	2	O tamanho ficou perfeito.	2025-12-16 13:46:39.453
cmq848j9u013plz65e3iigef4	cmq848ilb005clz65kg0tdzo3	user_052	4	Produto exatamente como na foto.	2026-04-18 15:22:18.604
cmq848j9v013rlz65236634x7	cmq848ily0062lz65yremo0se	user_026	5	Entrega antes do prazo, adorei!	2026-01-27 20:15:43.658
cmq848j9v013tlz65a2ieeef5	cmq848ij9002wlz659yg4uu4y	user_061	5	Presente pro meu filho, ele adorou!	2026-01-06 15:46:51.706
\.


--
-- Data for Name: StockMovement; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."StockMovement" (id, "productSizeId", type, quantity, reason, "createdAt") FROM stdin;
1493	363	out	5	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1494	368	out	2	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1495	373	out	11	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1496	442	out	8	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1497	455	out	21	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1498	490	out	6	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1499	544	out	11	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1500	565	out	13	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1501	569	out	9	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1502	576	out	15	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1503	609	out	3	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1504	621	out	13	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1505	623	out	17	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1506	735	out	20	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1507	775	out	2	Saída por venda ou ajuste	2026-06-10 10:46:01.318
1508	394	out	8	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1509	396	out	13	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1510	397	out	23	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1511	437	out	21	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1512	440	out	18	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1513	512	out	21	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1514	520	out	17	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1515	627	out	22	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1516	677	out	13	Saída por venda ou ajuste	2026-06-10 10:46:01.346
1517	793	out	23	Saída por venda ou ajuste	2026-06-10 10:46:01.346
679	361	in	9	Devolução	2026-04-01 08:34:43.479
680	362	out	16	Devolução	2026-04-29 12:40:29.209
681	362	in	18	Devolução	2026-05-06 05:58:39.443
682	363	in	11	Venda	2026-04-12 12:35:44.176
683	363	in	17	Devolução	2026-04-10 01:31:21.413
684	364	out	17	Devolução	2026-02-01 17:46:53.136
685	365	in	11	Compra fornecedor	2026-03-16 01:51:09.247
686	365	out	8	Ajuste inventário	2026-05-16 08:58:46.012
687	366	out	4	Compra fornecedor	2026-01-05 06:13:12.678
688	367	in	18	Ajuste inventário	2025-12-05 05:27:41.777
689	367	out	3	Devolução	2026-01-01 22:32:51.457
690	368	out	20	Venda	2026-05-07 14:03:54.015
691	369	out	14	Compra fornecedor	2026-01-27 11:25:05.013
692	370	in	5	Devolução	2026-06-07 22:56:35.791
693	371	in	12	Reposição	2026-03-07 03:23:03.576
694	372	in	6	Compra fornecedor	2026-02-16 15:28:44.511
695	372	in	12	Venda	2026-03-12 09:13:37.023
696	373	out	18	Compra fornecedor	2026-02-04 06:06:21.354
697	374	in	8	Venda	2026-05-23 22:45:22.619
698	374	out	12	Ajuste inventário	2026-05-26 20:06:34.644
699	375	out	3	Compra fornecedor	2026-04-08 13:55:09.646
700	375	in	1	Compra fornecedor	2026-05-18 17:38:47.556
701	375	out	8	Reposição	2026-03-23 19:09:30.021
702	376	in	3	Ajuste inventário	2026-02-25 21:17:13.484
703	376	in	3	Reposição	2026-01-16 09:15:50.05
704	376	in	11	Ajuste inventário	2026-02-22 13:34:57.232
705	377	in	13	Devolução	2025-12-05 18:06:52.067
706	377	in	18	Compra fornecedor	2026-02-15 23:37:49.416
707	378	in	10	Reposição	2026-01-07 20:55:00.468
708	378	in	18	Reposição	2026-02-28 16:40:29.734
709	378	in	17	Devolução	2026-01-20 09:04:46.02
710	379	in	18	Reposição	2026-05-31 16:23:29.252
711	380	in	9	Devolução	2026-04-20 13:35:11.95
712	380	in	2	Reposição	2026-02-25 13:32:51.256
713	380	in	13	Devolução	2026-01-10 00:44:12.846
714	381	in	4	Ajuste inventário	2026-04-18 19:21:14.288
715	381	out	17	Reposição	2025-12-27 17:09:44.879
716	381	in	12	Venda	2026-05-07 07:55:50.437
717	382	out	6	Ajuste inventário	2026-03-06 05:39:23.677
718	382	in	12	Ajuste inventário	2026-02-23 21:03:01.063
719	383	in	11	Venda	2025-12-01 06:01:06.969
720	384	in	8	Compra fornecedor	2026-03-07 11:02:17.665
721	385	out	17	Ajuste inventário	2026-03-09 15:03:29.845
722	385	out	9	Devolução	2026-02-21 13:47:12.485
723	386	out	4	Venda	2026-01-12 14:13:32.095
724	386	in	5	Ajuste inventário	2026-05-01 15:39:31.896
725	387	in	20	Ajuste inventário	2026-02-14 21:15:55.354
726	387	out	15	Devolução	2026-01-07 06:23:43.565
727	388	out	11	Devolução	2026-03-22 16:58:40.162
728	388	out	6	Ajuste inventário	2025-12-24 09:57:00.31
729	389	out	1	Devolução	2026-02-17 18:59:13.571
730	389	in	9	Compra fornecedor	2026-02-17 22:57:05.279
731	390	out	16	Devolução	2025-12-05 07:27:07.201
732	391	out	1	Reposição	2026-01-08 01:12:49.196
733	391	in	10	Ajuste inventário	2026-05-19 01:05:40.43
734	391	in	2	Reposição	2026-05-24 21:38:26.356
735	392	in	2	Devolução	2025-12-15 08:10:45.443
736	392	in	11	Compra fornecedor	2025-12-02 11:15:00.068
737	393	in	4	Compra fornecedor	2026-01-08 23:13:39.061
738	393	out	17	Ajuste inventário	2026-03-07 05:53:07.442
739	394	in	6	Ajuste inventário	2026-04-20 12:21:11.658
740	395	in	3	Devolução	2026-02-08 02:51:51.823
741	395	out	11	Devolução	2026-05-22 09:14:25.441
742	396	in	11	Venda	2026-05-27 19:14:50.035
743	396	in	3	Ajuste inventário	2025-12-25 03:21:46.156
744	396	in	12	Venda	2025-12-14 14:43:36.483
745	397	out	17	Venda	2026-04-24 13:23:22.189
746	397	in	5	Compra fornecedor	2026-02-04 13:25:55.071
747	397	in	20	Compra fornecedor	2026-02-22 19:36:53.327
748	398	in	12	Compra fornecedor	2026-04-28 22:38:25.64
749	398	in	12	Devolução	2026-05-18 22:01:55.404
750	399	out	8	Ajuste inventário	2026-04-26 01:25:50.368
751	399	out	3	Venda	2026-04-27 11:05:30.08
752	399	in	7	Ajuste inventário	2026-03-25 12:58:19.363
753	400	in	5	Compra fornecedor	2025-12-09 01:06:53.454
754	400	in	11	Venda	2026-04-12 02:42:07.537
755	400	out	6	Venda	2026-06-07 04:33:02.974
756	401	out	10	Devolução	2026-04-26 02:44:45.488
757	402	out	19	Ajuste inventário	2026-01-15 02:51:29.581
758	402	in	16	Devolução	2026-01-03 18:45:37.526
759	403	out	6	Ajuste inventário	2026-04-21 21:09:55.018
760	404	in	4	Venda	2026-01-18 23:51:39.588
761	404	in	11	Venda	2025-12-13 20:03:00.31
762	405	out	10	Reposição	2026-05-11 06:18:40.493
763	406	out	4	Devolução	2026-01-21 18:04:25.253
764	406	out	2	Devolução	2025-12-19 23:42:44.258
765	407	in	14	Ajuste inventário	2026-02-08 14:20:32.432
766	407	out	19	Compra fornecedor	2026-05-24 13:58:08.483
767	407	out	17	Venda	2026-02-28 15:36:14.275
768	408	in	11	Compra fornecedor	2025-12-31 03:12:24.863
769	408	out	15	Ajuste inventário	2025-12-28 05:29:37.555
770	408	in	8	Ajuste inventário	2026-05-15 08:42:01.432
771	409	in	18	Ajuste inventário	2026-04-21 08:00:40.971
772	409	in	14	Venda	2026-02-22 07:01:00.807
773	410	in	2	Venda	2025-12-20 00:04:56.965
774	411	in	13	Compra fornecedor	2026-05-29 13:56:10.481
775	411	out	5	Devolução	2025-12-06 07:42:15.324
776	412	in	1	Venda	2025-12-15 14:26:00.765
777	412	in	14	Ajuste inventário	2026-02-11 21:46:23.22
778	412	in	5	Compra fornecedor	2026-05-03 10:11:39.179
779	413	in	7	Venda	2026-04-01 11:58:33.903
780	414	in	12	Ajuste inventário	2026-01-27 15:53:16.767
781	414	in	14	Compra fornecedor	2026-02-27 12:22:30.302
782	415	in	12	Reposição	2026-05-17 17:35:38.03
783	416	in	12	Compra fornecedor	2026-04-25 10:22:15.27
784	417	out	1	Venda	2026-05-07 03:58:17.101
785	417	out	18	Compra fornecedor	2026-03-24 10:09:20.461
786	418	in	11	Devolução	2026-01-06 08:17:48.747
787	418	in	13	Ajuste inventário	2026-05-13 00:32:32.203
788	419	in	20	Reposição	2025-12-06 12:12:24.901
789	420	in	1	Venda	2026-01-21 04:13:01.95
790	420	out	15	Reposição	2026-04-15 04:29:55.772
791	421	out	20	Devolução	2026-04-24 17:16:01.14
792	421	out	3	Devolução	2026-05-11 15:40:30.606
793	422	in	11	Devolução	2026-01-17 00:27:10.247
794	422	out	6	Venda	2026-02-22 21:19:30.922
795	422	in	9	Ajuste inventário	2026-01-26 17:33:53.023
796	423	in	4	Ajuste inventário	2026-04-29 08:41:11.191
797	424	in	15	Venda	2026-05-30 18:50:14.795
798	425	in	6	Ajuste inventário	2025-12-16 00:53:58.874
799	425	in	4	Devolução	2026-03-08 15:11:22.41
800	426	out	9	Ajuste inventário	2026-01-10 16:22:12.252
801	427	out	2	Venda	2026-01-16 04:04:08.484
802	427	in	8	Reposição	2026-05-23 10:38:08.255
803	428	in	13	Ajuste inventário	2026-02-21 11:23:18.087
804	429	in	9	Devolução	2026-04-25 02:02:09.16
805	430	in	19	Ajuste inventário	2026-05-12 23:34:20.187
806	431	in	11	Reposição	2025-12-19 13:06:05.731
807	432	in	18	Reposição	2026-06-07 14:49:27.356
808	433	in	1	Compra fornecedor	2026-02-05 06:48:40.18
809	433	out	18	Compra fornecedor	2026-03-28 17:40:06.713
810	433	out	10	Compra fornecedor	2026-02-25 23:37:48.88
811	434	in	9	Compra fornecedor	2026-06-07 20:37:46.792
812	435	in	20	Compra fornecedor	2026-01-05 22:55:24.483
813	435	out	6	Devolução	2026-01-21 14:11:33.655
814	436	in	4	Devolução	2026-04-01 19:52:13.179
815	437	out	4	Reposição	2026-04-01 22:19:15.328
816	437	out	17	Ajuste inventário	2026-02-27 12:58:33.692
817	437	out	6	Compra fornecedor	2026-03-28 03:38:25.95
818	438	in	1	Devolução	2026-02-07 19:23:54.429
819	439	in	10	Ajuste inventário	2026-04-03 14:37:15.771
820	439	in	20	Reposição	2026-05-11 03:00:26.05
821	440	in	11	Devolução	2026-04-12 06:25:31.504
822	440	out	15	Reposição	2026-02-05 05:11:11.21
823	440	out	14	Devolução	2026-01-31 21:48:37.125
824	441	out	5	Devolução	2026-02-13 12:08:05.354
825	441	out	10	Venda	2026-02-11 13:16:14.776
826	442	in	13	Reposição	2026-05-11 13:39:15.523
827	442	in	20	Devolução	2025-12-31 20:00:02.012
828	443	in	17	Compra fornecedor	2026-01-14 07:09:06.136
829	444	in	16	Devolução	2025-12-10 14:44:32.371
830	444	out	5	Ajuste inventário	2026-04-02 09:57:14.378
831	445	out	10	Compra fornecedor	2026-05-28 01:54:53.728
832	446	out	11	Reposição	2025-12-07 07:05:18.915
833	446	in	10	Compra fornecedor	2026-04-14 02:56:03.884
834	447	in	1	Devolução	2026-05-08 10:10:13.615
835	448	in	5	Devolução	2025-12-03 07:20:48.515
836	449	out	19	Venda	2026-04-25 09:16:02.372
837	449	in	19	Venda	2026-01-30 15:04:29.099
838	450	in	3	Compra fornecedor	2026-05-10 04:34:53.048
839	450	in	18	Ajuste inventário	2025-12-01 18:21:18.977
840	450	in	4	Devolução	2026-04-09 01:52:33.896
841	451	in	14	Reposição	2026-04-16 20:40:43.337
842	451	out	5	Reposição	2026-01-31 05:12:07.686
843	452	out	19	Devolução	2026-01-13 23:21:03.725
844	453	in	18	Compra fornecedor	2026-05-06 22:26:23.76
845	454	out	19	Ajuste inventário	2026-02-08 08:37:51.538
846	455	in	14	Devolução	2025-12-30 01:10:23.29
847	455	out	4	Reposição	2026-01-17 14:36:18.32
848	455	out	6	Venda	2026-01-28 21:36:30.415
849	456	in	18	Venda	2026-04-11 11:29:09.242
850	456	out	4	Ajuste inventário	2026-03-02 17:38:51.987
851	457	in	14	Venda	2026-04-14 18:49:18.474
852	458	in	13	Compra fornecedor	2026-05-14 06:00:52.85
853	458	in	13	Reposição	2026-03-24 03:29:30.691
854	458	out	9	Compra fornecedor	2026-05-01 13:03:10.922
855	459	out	1	Reposição	2025-12-30 22:49:13.164
856	460	in	10	Venda	2026-02-27 21:13:59.486
857	460	in	9	Venda	2026-03-18 13:53:38.383
858	461	out	11	Compra fornecedor	2026-03-01 15:25:27.761
859	462	in	14	Ajuste inventário	2026-01-02 05:11:04.035
860	462	out	8	Venda	2026-05-07 08:15:03.15
861	462	out	18	Devolução	2026-04-20 18:07:42.673
862	463	in	16	Devolução	2025-12-14 04:57:19.987
863	463	in	2	Devolução	2026-03-14 20:02:52.135
864	463	out	4	Devolução	2026-01-10 04:48:52.321
865	464	out	15	Reposição	2026-05-12 04:11:20.543
866	464	in	7	Devolução	2026-03-05 17:33:12.494
867	465	in	9	Venda	2026-05-03 20:28:37.026
868	466	in	2	Reposição	2026-06-01 12:20:22.898
869	466	out	8	Reposição	2026-04-05 22:22:55.466
870	467	out	8	Ajuste inventário	2026-01-05 08:45:45.446
871	467	in	16	Reposição	2026-04-17 15:32:22.308
872	467	in	2	Compra fornecedor	2026-02-10 02:55:28.469
873	468	out	1	Reposição	2026-02-08 03:33:40.71
874	468	out	11	Compra fornecedor	2026-05-01 12:53:56.111
875	469	in	11	Compra fornecedor	2026-04-04 14:40:16.34
876	469	out	2	Venda	2026-05-21 10:31:27.692
877	470	out	11	Ajuste inventário	2026-02-17 23:59:50.608
878	471	in	15	Devolução	2026-04-07 10:30:33.749
879	472	in	1	Reposição	2026-03-04 07:35:30.202
880	472	in	3	Compra fornecedor	2026-02-05 06:49:56.105
881	473	out	18	Reposição	2026-05-22 11:13:39.233
882	473	in	5	Devolução	2026-01-10 14:31:52.195
883	473	in	5	Ajuste inventário	2026-01-31 03:32:00.374
884	474	in	18	Ajuste inventário	2026-05-16 21:12:37.307
885	475	in	12	Ajuste inventário	2026-04-05 10:23:14.085
886	476	out	19	Venda	2026-01-09 05:07:24.76
887	476	in	3	Venda	2026-01-09 11:58:10.315
888	477	in	1	Devolução	2026-03-26 22:44:07.228
889	478	out	3	Venda	2025-12-25 14:38:28.828
890	478	out	15	Venda	2026-02-03 20:22:12.492
891	479	in	17	Venda	2026-01-09 21:50:28.737
892	479	out	14	Devolução	2026-03-16 00:00:49.295
893	479	in	15	Venda	2026-02-06 00:37:27.135
894	480	in	11	Devolução	2026-06-08 23:39:25.958
895	480	in	9	Reposição	2026-05-03 01:05:39.075
896	480	out	10	Venda	2026-03-26 15:48:39.602
897	481	out	3	Ajuste inventário	2026-02-27 07:07:55.633
898	481	out	14	Ajuste inventário	2025-12-05 22:49:26.256
899	481	in	2	Reposição	2026-04-22 23:29:06.332
900	482	in	18	Venda	2026-01-17 07:31:51.698
901	482	out	17	Reposição	2026-01-07 02:05:01.655
902	483	in	5	Devolução	2026-01-15 14:34:30.682
903	484	in	8	Reposição	2026-01-16 12:20:29.381
904	484	in	7	Compra fornecedor	2026-03-04 01:55:02.237
905	485	out	17	Ajuste inventário	2025-12-07 02:48:56.465
906	486	in	13	Devolução	2026-01-07 13:49:13.375
907	486	out	19	Reposição	2026-01-27 23:17:52.466
908	487	out	7	Reposição	2025-12-02 19:12:23.754
909	487	in	16	Devolução	2026-04-29 21:44:09.516
910	488	in	5	Reposição	2026-01-03 16:11:49.422
911	488	out	11	Compra fornecedor	2026-01-24 04:48:08.274
912	488	in	18	Devolução	2026-03-29 03:47:13.979
913	489	in	3	Ajuste inventário	2025-12-06 10:02:39.596
914	489	in	9	Ajuste inventário	2025-12-09 09:59:13.795
915	490	in	2	Reposição	2025-12-19 21:11:07.699
916	490	out	1	Reposição	2025-12-04 17:55:19.123
917	491	in	15	Ajuste inventário	2025-12-14 11:20:24.453
918	491	out	2	Reposição	2025-12-10 16:26:29.771
919	492	out	8	Venda	2026-04-24 05:27:17.223
920	492	out	19	Venda	2026-03-07 04:30:28.474
921	493	in	16	Venda	2026-02-20 08:21:41.24
922	494	out	19	Devolução	2026-02-28 14:24:59.897
923	494	out	13	Compra fornecedor	2025-12-19 04:13:33.434
924	495	in	17	Venda	2026-02-11 23:46:13.566
925	496	out	14	Venda	2025-12-23 05:42:32.979
926	496	in	3	Venda	2026-03-15 20:09:45.684
927	496	in	3	Compra fornecedor	2026-03-31 01:50:18.039
928	497	in	6	Venda	2025-12-19 08:54:18.383
929	497	in	18	Reposição	2026-04-03 01:19:39.758
930	498	out	1	Reposição	2025-12-19 19:13:20.984
931	498	out	6	Venda	2026-04-02 17:27:35.578
932	498	in	6	Venda	2026-02-03 21:27:33.887
933	499	out	10	Compra fornecedor	2026-05-04 02:14:00.466
934	499	in	5	Venda	2026-05-17 06:23:15.983
935	499	in	3	Ajuste inventário	2026-01-22 12:25:55.442
936	500	in	9	Compra fornecedor	2025-12-27 19:11:11.715
937	500	out	18	Venda	2025-12-22 13:22:47.593
938	501	out	15	Venda	2026-04-09 03:19:19.041
939	502	out	2	Compra fornecedor	2025-12-14 00:28:42.612
940	502	out	16	Ajuste inventário	2025-12-16 21:30:18.539
941	503	in	12	Venda	2025-12-14 20:41:49.126
942	504	in	10	Compra fornecedor	2026-05-02 11:37:12.949
943	504	in	19	Ajuste inventário	2026-05-28 20:54:03.829
944	505	in	19	Venda	2026-02-08 11:19:41.743
945	505	in	12	Devolução	2026-04-26 23:14:51.027
946	505	in	9	Compra fornecedor	2026-04-05 19:18:02.559
947	506	out	5	Venda	2026-05-11 16:07:58.185
948	507	in	10	Compra fornecedor	2026-06-06 05:10:18.902
949	507	in	6	Ajuste inventário	2025-12-15 14:30:50.369
950	508	out	18	Venda	2026-01-31 21:30:09.452
951	508	in	14	Ajuste inventário	2026-02-26 06:37:10.032
952	509	in	1	Compra fornecedor	2026-01-12 10:34:25.523
953	509	in	11	Venda	2026-01-04 07:00:09.06
954	509	out	5	Devolução	2026-02-05 08:38:52.694
955	510	out	1	Ajuste inventário	2026-05-12 08:10:07.317
956	510	in	6	Venda	2026-04-09 06:00:40.561
957	511	in	2	Venda	2026-01-14 05:28:31.299
958	511	in	5	Compra fornecedor	2025-12-25 19:38:43.04
959	511	out	3	Venda	2026-01-16 18:58:18.125
960	512	out	16	Compra fornecedor	2026-05-08 21:34:22.909
961	512	in	6	Ajuste inventário	2026-05-06 05:09:14.582
962	512	out	18	Reposição	2026-01-15 05:50:11.924
963	513	in	18	Compra fornecedor	2026-05-13 16:19:30.52
964	513	in	8	Compra fornecedor	2026-02-01 02:34:02.213
965	514	in	9	Compra fornecedor	2026-02-09 11:24:38.946
966	514	in	6	Reposição	2026-02-21 20:23:04.006
967	514	in	12	Compra fornecedor	2026-01-19 06:49:32.627
968	515	in	14	Ajuste inventário	2026-04-26 16:16:12.578
969	515	out	3	Venda	2026-01-30 17:08:37.416
970	516	out	16	Ajuste inventário	2026-03-13 04:14:05.088
971	517	in	16	Ajuste inventário	2026-01-20 09:47:49.372
972	518	in	11	Ajuste inventário	2026-02-11 10:09:28.816
973	518	out	18	Compra fornecedor	2026-05-27 09:17:28.78
974	519	out	18	Ajuste inventário	2026-05-08 15:28:54.389
975	519	in	4	Devolução	2026-05-15 07:51:07.58
976	520	out	11	Venda	2026-06-05 04:48:06.823
977	520	in	15	Ajuste inventário	2026-03-26 14:48:58.615
978	520	in	20	Ajuste inventário	2026-05-28 04:18:41.742
979	521	in	15	Devolução	2026-05-21 22:41:40.492
980	522	in	10	Compra fornecedor	2026-06-04 03:52:06.401
981	523	in	2	Ajuste inventário	2026-02-11 04:35:59.75
982	524	in	8	Reposição	2026-01-09 11:57:34.473
983	525	out	16	Reposição	2026-06-02 23:26:25.134
984	525	in	14	Compra fornecedor	2026-02-22 19:38:19.112
985	526	in	15	Devolução	2026-01-18 03:49:09.422
986	526	out	10	Venda	2026-05-14 10:17:47.116
987	526	in	16	Ajuste inventário	2026-02-11 13:20:06.685
988	527	in	8	Compra fornecedor	2026-05-20 03:13:50.271
989	527	in	18	Venda	2026-04-01 11:23:05.142
990	527	out	4	Ajuste inventário	2026-04-25 05:48:49.869
991	528	in	13	Devolução	2026-05-09 19:05:09.702
992	528	out	8	Reposição	2026-02-21 13:19:56.22
993	529	in	3	Compra fornecedor	2026-01-23 11:47:59.218
994	530	out	2	Venda	2025-12-18 15:37:21.713
995	531	in	12	Reposição	2026-05-16 08:32:18.038
996	532	in	6	Compra fornecedor	2026-04-27 21:48:56.268
997	532	in	12	Venda	2026-01-16 06:06:43.528
998	532	out	16	Reposição	2026-03-19 16:14:27.763
999	533	out	19	Venda	2026-03-24 02:39:25.664
1000	533	out	8	Reposição	2026-06-05 03:54:08.726
1001	533	in	8	Ajuste inventário	2026-05-12 00:28:46.418
1002	534	in	11	Compra fornecedor	2026-04-27 22:07:16.651
1003	534	in	10	Devolução	2025-12-09 19:48:23.784
1004	535	in	5	Venda	2026-06-08 15:40:36.498
1005	536	out	19	Venda	2026-01-26 10:40:15.339
1006	536	in	17	Devolução	2026-01-14 20:56:39.264
1007	536	in	11	Ajuste inventário	2026-05-18 20:35:54.392
1008	537	out	9	Devolução	2026-05-26 17:57:34.917
1009	538	in	5	Ajuste inventário	2026-02-20 23:53:15.224
1010	538	out	19	Compra fornecedor	2026-02-24 20:28:31.847
1011	538	in	18	Reposição	2026-03-01 22:52:46.81
1012	539	out	14	Venda	2026-05-18 14:34:41.093
1013	540	in	12	Venda	2026-03-22 01:20:51.087
1014	540	in	7	Compra fornecedor	2026-01-18 00:20:52.225
1015	540	in	11	Devolução	2026-03-26 15:05:13.426
1016	541	in	17	Ajuste inventário	2026-06-06 16:14:47.021
1017	542	out	2	Devolução	2026-05-11 18:30:15.691
1018	542	out	20	Venda	2026-03-20 07:41:14.984
1019	543	in	4	Reposição	2026-05-22 19:38:03.774
1020	543	in	6	Compra fornecedor	2026-04-09 21:58:03.364
1021	544	out	14	Devolução	2026-03-17 06:52:25.135
1022	545	out	13	Reposição	2026-03-13 02:20:42.741
1023	546	in	13	Devolução	2026-04-27 22:01:30.665
1024	546	out	5	Reposição	2026-06-08 02:01:49.693
1025	547	out	6	Devolução	2026-02-03 05:47:08.875
1026	548	in	10	Ajuste inventário	2026-01-31 22:40:00.992
1027	548	out	3	Devolução	2026-06-05 07:30:00.305
1028	548	out	18	Venda	2026-01-31 17:28:58.532
1029	549	in	19	Compra fornecedor	2026-05-21 13:44:22.051
1030	549	in	17	Compra fornecedor	2025-12-08 05:52:48.576
1031	550	in	15	Ajuste inventário	2025-12-21 16:09:42.118
1032	550	out	10	Devolução	2026-03-06 04:39:13.71
1033	551	in	5	Ajuste inventário	2026-02-22 15:23:54.66
1034	551	in	14	Devolução	2025-12-09 17:23:43.64
1035	552	in	2	Venda	2025-12-10 19:29:11.743
1036	553	out	2	Compra fornecedor	2026-04-16 15:57:08.528
1037	553	in	16	Reposição	2026-03-24 20:48:35.186
1038	553	in	16	Reposição	2026-03-21 05:51:16.808
1039	554	in	8	Devolução	2026-05-26 06:38:10.352
1040	554	out	16	Compra fornecedor	2026-01-10 06:32:00.425
1041	555	in	13	Venda	2026-04-30 09:23:19.468
1042	555	out	10	Compra fornecedor	2026-04-02 21:17:37.761
1043	556	out	1	Compra fornecedor	2026-01-30 20:51:02.107
1044	556	in	17	Reposição	2026-01-19 03:18:05.75
1045	556	in	5	Reposição	2026-03-06 12:04:51.477
1046	557	in	13	Venda	2026-02-03 12:56:01.234
1047	557	out	12	Venda	2025-12-29 09:01:44.16
1048	558	in	13	Reposição	2025-12-07 21:00:09.636
1049	559	in	11	Ajuste inventário	2026-04-18 12:24:41.633
1050	560	in	18	Reposição	2026-06-01 04:03:28.072
1051	561	out	5	Compra fornecedor	2025-12-02 05:35:08.383
1169	624	in	9	Venda	2026-01-21 00:36:24.207
1052	561	out	19	Compra fornecedor	2026-04-01 00:27:45.734
1053	562	out	13	Reposição	2026-02-04 11:42:34.283
1054	562	in	11	Venda	2025-12-01 06:30:04.755
1055	563	out	15	Venda	2026-03-10 05:38:23.994
1056	563	in	1	Ajuste inventário	2025-12-24 12:20:55.094
1057	564	out	1	Reposição	2026-03-08 21:33:52.057
1058	565	in	12	Venda	2026-05-10 06:16:48.602
1059	565	in	6	Reposição	2026-02-10 04:25:05.152
1060	565	in	8	Devolução	2026-01-18 07:52:46.189
1061	566	in	12	Devolução	2026-02-17 12:42:19.008
1062	566	in	2	Venda	2025-12-30 09:19:09.776
1063	567	in	19	Compra fornecedor	2026-03-24 23:23:52.647
1064	567	in	11	Reposição	2026-01-09 01:15:19.535
1065	568	out	7	Compra fornecedor	2026-01-17 18:15:55.703
1066	569	out	4	Ajuste inventário	2026-03-02 16:05:16.896
1067	570	out	1	Reposição	2026-03-21 13:38:01.305
1068	570	out	9	Ajuste inventário	2026-05-17 01:43:43.808
1069	571	in	4	Ajuste inventário	2026-05-21 01:15:47.678
1070	571	in	14	Devolução	2026-04-27 22:45:23.299
1071	571	in	9	Reposição	2026-03-27 03:40:05.646
1072	572	in	14	Venda	2026-01-16 13:38:30.998
1073	572	out	11	Devolução	2026-01-21 04:38:22.264
1074	573	in	12	Venda	2026-04-15 22:27:23.019
1075	573	out	6	Venda	2026-04-05 14:51:48.492
1076	574	out	14	Venda	2026-02-14 00:31:57.919
1077	574	in	4	Devolução	2025-12-18 16:56:27.11
1078	575	out	18	Reposição	2026-02-16 15:14:19.199
1079	575	out	4	Compra fornecedor	2026-04-29 03:06:17.135
1080	575	in	20	Devolução	2026-04-23 03:43:50.444
1081	576	out	1	Reposição	2026-01-02 05:29:09.111
1082	577	in	2	Ajuste inventário	2026-01-02 03:56:42.428
1083	577	out	5	Venda	2026-03-18 19:31:22.749
1084	578	in	17	Compra fornecedor	2025-12-16 14:50:21.293
1085	579	in	11	Venda	2026-04-30 01:59:50.471
1086	580	in	8	Devolução	2026-06-02 14:13:10.952
1087	581	out	7	Compra fornecedor	2026-01-01 11:25:26.557
1088	581	in	7	Compra fornecedor	2026-02-21 04:55:48.328
1089	582	in	6	Reposição	2026-01-27 09:20:34.176
1090	583	out	9	Venda	2026-02-09 02:42:25.304
1091	583	in	8	Venda	2025-12-23 03:04:12.485
1092	584	in	13	Ajuste inventário	2026-05-15 18:54:11.966
1093	584	in	10	Reposição	2026-04-16 17:47:04.409
1094	584	in	4	Devolução	2026-05-08 19:28:55.289
1095	585	in	13	Ajuste inventário	2026-04-09 05:42:28.811
1096	585	in	20	Devolução	2026-03-30 22:09:15.733
1097	586	in	9	Devolução	2026-03-31 09:42:59.148
1098	587	out	17	Compra fornecedor	2026-02-24 14:49:55.123
1099	588	in	14	Ajuste inventário	2026-06-07 10:56:52.526
1100	588	in	10	Compra fornecedor	2025-12-31 08:37:19.787
1101	589	in	20	Reposição	2026-02-02 20:39:35.952
1102	590	in	17	Devolução	2025-12-01 01:09:04.292
1103	590	out	15	Ajuste inventário	2026-05-21 13:18:37.865
1104	591	in	13	Reposição	2026-01-26 18:37:12.974
1105	591	in	4	Reposição	2026-04-21 10:52:01.41
1106	591	in	20	Devolução	2026-05-11 14:22:50.952
1107	592	in	14	Ajuste inventário	2026-04-06 15:54:44.797
1108	593	in	17	Compra fornecedor	2026-01-21 11:14:25.479
1109	593	in	8	Venda	2026-05-03 00:02:02.124
1110	593	out	9	Devolução	2025-12-11 00:41:31.482
1111	594	out	13	Devolução	2026-02-15 13:40:44.045
1112	595	out	20	Venda	2026-03-15 19:39:31.719
1113	595	out	20	Venda	2026-03-10 09:52:27.016
1114	596	in	5	Compra fornecedor	2026-03-19 18:53:54.491
1115	597	in	7	Compra fornecedor	2026-05-30 14:00:59.715
1116	598	out	9	Reposição	2026-03-02 19:55:51.925
1117	598	in	10	Devolução	2026-03-18 15:57:06.17
1118	599	in	13	Ajuste inventário	2025-12-19 05:38:57.037
1119	600	in	17	Compra fornecedor	2026-02-05 05:08:19.637
1120	601	out	6	Reposição	2026-03-04 17:25:07.419
1121	601	in	20	Reposição	2026-02-07 02:54:32.53
1122	601	in	7	Compra fornecedor	2025-12-04 22:42:05.628
1123	602	out	18	Ajuste inventário	2026-03-18 09:25:56.273
1124	603	in	1	Devolução	2025-12-28 16:08:41.387
1125	604	out	5	Compra fornecedor	2026-03-30 05:58:07.09
1126	604	out	15	Venda	2026-03-22 14:28:09.1
1127	604	in	20	Devolução	2026-03-27 17:34:48.998
1128	605	out	7	Compra fornecedor	2026-02-14 01:36:13.183
1129	605	out	13	Compra fornecedor	2026-05-18 03:34:15.158
1130	606	in	6	Ajuste inventário	2026-03-14 11:46:39.742
1131	607	out	7	Devolução	2026-01-03 07:28:00.672
1132	607	out	14	Devolução	2026-03-02 11:53:00.567
1133	608	in	18	Compra fornecedor	2025-12-29 06:15:40.626
1134	608	in	15	Compra fornecedor	2026-05-24 22:41:15.189
1135	609	out	10	Devolução	2026-02-01 09:18:34.296
1136	609	in	19	Reposição	2026-05-26 03:26:06.61
1137	609	in	5	Venda	2026-02-22 20:22:43.221
1138	610	in	13	Devolução	2026-04-19 18:08:43.383
1139	611	in	1	Devolução	2026-03-12 06:50:21.947
1140	611	in	2	Venda	2026-04-01 06:53:44.269
1141	611	out	19	Ajuste inventário	2026-03-14 15:21:45.005
1142	612	in	11	Reposição	2026-04-30 02:05:35.549
1143	612	out	5	Ajuste inventário	2026-05-10 01:40:22.463
1144	612	in	16	Compra fornecedor	2026-05-03 13:01:17.482
1145	613	in	10	Devolução	2026-03-31 10:22:09.221
1146	613	in	18	Ajuste inventário	2026-03-07 02:45:17.573
1147	614	out	4	Ajuste inventário	2026-05-02 16:16:05.745
1148	615	in	5	Devolução	2026-03-18 05:23:44.612
1149	616	out	13	Devolução	2026-03-15 08:26:37.16
1150	616	in	13	Reposição	2026-02-18 04:03:45.125
1151	616	in	8	Ajuste inventário	2025-12-14 23:26:17.851
1152	617	in	12	Venda	2026-03-27 11:46:14.295
1153	617	out	20	Ajuste inventário	2025-12-09 02:12:53.1
1154	618	out	7	Compra fornecedor	2025-12-28 05:59:19.938
1155	618	in	1	Reposição	2026-03-13 17:54:11.31
1156	618	out	17	Devolução	2026-05-17 16:40:53.92
1157	619	in	20	Devolução	2025-12-14 10:14:49.012
1158	619	out	14	Reposição	2026-02-09 20:34:13.887
1159	619	in	1	Venda	2025-12-12 19:49:53.008
1160	620	out	5	Ajuste inventário	2026-01-08 18:16:45.777
1161	620	in	11	Compra fornecedor	2026-03-22 14:20:13.625
1162	621	in	11	Ajuste inventário	2025-12-06 12:10:49.444
1163	622	out	15	Compra fornecedor	2026-03-23 13:41:03.814
1164	622	out	1	Reposição	2026-05-22 04:34:45.594
1165	623	out	15	Devolução	2026-04-08 22:32:20.914
1166	623	out	14	Venda	2026-02-10 10:22:57.453
1167	623	out	1	Devolução	2026-05-31 09:47:08.301
1168	624	out	14	Compra fornecedor	2026-05-07 03:09:54.217
1170	625	in	13	Reposição	2026-01-26 10:43:27.331
1171	625	in	14	Devolução	2026-05-21 05:09:30.425
1172	626	out	11	Devolução	2025-12-18 08:39:13.568
1173	627	in	6	Ajuste inventário	2026-05-04 08:47:56.882
1174	627	out	12	Ajuste inventário	2026-02-20 04:30:56.006
1175	628	in	6	Venda	2026-03-27 03:46:11.353
1176	628	in	1	Reposição	2026-04-13 18:47:52.567
1177	628	out	2	Venda	2026-05-27 17:20:35.193
1178	629	in	4	Ajuste inventário	2026-02-06 14:35:11.496
1179	629	out	20	Venda	2025-12-12 19:44:32.018
1180	629	out	1	Reposição	2026-04-06 06:28:55.89
1181	630	in	1	Ajuste inventário	2026-02-24 14:50:33.974
1182	630	in	20	Reposição	2026-04-05 16:48:50.463
1183	630	in	15	Devolução	2026-02-19 18:18:39.138
1184	631	in	6	Compra fornecedor	2026-05-01 03:15:22.93
1185	631	out	7	Compra fornecedor	2025-12-08 15:04:25.792
1186	631	in	10	Venda	2026-01-19 04:57:31.424
1187	632	in	15	Compra fornecedor	2026-02-08 09:08:41.647
1188	632	in	4	Compra fornecedor	2026-05-15 08:35:06.828
1189	632	out	2	Venda	2026-06-01 01:46:56.872
1190	633	out	20	Reposição	2026-02-28 12:46:42.2
1191	634	in	18	Reposição	2026-03-26 11:55:52.234
1192	635	out	14	Reposição	2026-04-10 05:27:15.124
1193	635	in	5	Devolução	2026-02-28 22:52:36.038
1194	636	out	14	Reposição	2026-01-01 10:24:49.962
1195	637	in	19	Compra fornecedor	2026-04-04 16:05:52.215
1196	637	out	8	Reposição	2026-05-11 15:19:54.919
1197	638	in	6	Venda	2026-05-19 02:14:18.997
1198	639	in	10	Ajuste inventário	2025-12-18 15:40:37.832
1199	639	in	7	Ajuste inventário	2026-04-05 15:01:49.81
1200	639	out	3	Reposição	2026-04-08 22:09:05.961
1201	640	in	18	Reposição	2026-02-22 07:08:47.6
1202	640	in	19	Devolução	2026-05-26 08:47:55.608
1203	640	out	13	Compra fornecedor	2026-01-25 09:09:06.721
1204	641	in	2	Devolução	2026-04-19 11:03:33.843
1205	641	in	6	Ajuste inventário	2025-12-05 03:21:27.399
1206	641	out	7	Reposição	2026-05-02 11:59:41.001
1207	642	in	11	Ajuste inventário	2026-02-03 09:18:05.044
1208	642	out	10	Reposição	2025-12-20 23:47:46.471
1209	643	out	12	Ajuste inventário	2026-03-10 09:35:29.933
1210	644	out	2	Ajuste inventário	2026-03-19 10:42:20.565
1211	645	in	3	Ajuste inventário	2025-12-18 08:27:14.609
1212	645	in	1	Ajuste inventário	2025-12-17 01:28:07.412
1213	645	in	19	Devolução	2025-12-15 16:59:50.044
1214	646	out	18	Compra fornecedor	2026-05-04 08:46:37.779
1215	647	in	20	Devolução	2026-05-11 12:32:31.338
1216	647	in	12	Devolução	2026-01-31 02:25:21.965
1217	648	in	3	Venda	2026-04-20 11:09:38.546
1218	648	out	10	Devolução	2025-12-20 13:50:57.542
1219	649	in	16	Devolução	2026-01-18 17:33:04.321
1220	649	in	20	Compra fornecedor	2026-04-09 18:42:27.126
1221	649	out	7	Reposição	2026-05-27 09:28:42.266
1222	650	in	7	Compra fornecedor	2026-05-07 23:25:36.294
1223	650	out	13	Venda	2025-12-15 14:15:29.829
1224	651	out	19	Devolução	2026-05-07 10:50:56.172
1225	651	out	13	Ajuste inventário	2026-05-21 09:39:17.739
1226	652	in	2	Venda	2026-03-14 07:23:38.079
1227	652	in	5	Ajuste inventário	2026-01-02 06:22:50.798
1228	653	in	12	Compra fornecedor	2026-01-31 16:04:05.126
1229	653	in	17	Devolução	2026-01-12 08:46:38.226
1230	653	out	5	Reposição	2026-05-30 21:41:05.584
1231	654	out	17	Devolução	2026-04-12 23:13:07.793
1232	654	out	12	Devolução	2026-05-11 08:39:55.808
1233	655	out	5	Venda	2025-12-28 23:41:38.891
1234	655	in	10	Reposição	2026-03-27 03:06:41.245
1235	656	in	17	Devolução	2026-04-12 10:17:06.116
1236	656	in	11	Devolução	2026-03-22 22:16:18.198
1237	657	out	20	Devolução	2026-06-03 15:55:42.361
1238	657	out	6	Ajuste inventário	2026-01-15 07:04:10.331
1239	657	in	4	Compra fornecedor	2026-04-16 18:27:48.182
1240	658	in	16	Reposição	2026-06-04 07:21:57.227
1241	658	out	10	Venda	2026-01-12 05:46:15.722
1242	659	in	20	Compra fornecedor	2026-01-07 11:15:32.009
1243	660	out	8	Ajuste inventário	2025-12-29 05:43:33.725
1244	661	in	11	Compra fornecedor	2026-04-30 04:43:05.586
1245	661	in	15	Ajuste inventário	2026-02-11 11:36:01.07
1246	662	in	11	Ajuste inventário	2026-04-20 16:45:49.475
1247	663	out	3	Devolução	2025-12-16 06:16:24.103
1248	663	out	8	Compra fornecedor	2026-05-13 18:57:06.868
1249	663	out	8	Compra fornecedor	2026-03-13 02:08:05.212
1250	664	in	20	Compra fornecedor	2026-03-18 23:28:16.597
1251	664	out	11	Compra fornecedor	2026-03-21 17:57:36.601
1252	664	out	15	Devolução	2026-04-26 10:43:24.45
1253	665	in	9	Devolução	2026-05-31 03:37:37.36
1254	665	in	11	Venda	2026-01-12 19:47:46.169
1255	666	out	1	Devolução	2026-05-05 18:39:45.067
1256	666	out	4	Ajuste inventário	2026-02-20 01:24:42.131
1257	667	in	16	Compra fornecedor	2026-06-03 04:27:52.248
1258	668	out	16	Venda	2026-04-22 19:23:22.963
1259	668	in	18	Compra fornecedor	2026-01-25 13:06:15.316
1260	668	in	7	Ajuste inventário	2026-03-04 13:26:50.869
1261	669	in	8	Venda	2026-02-16 15:33:44.868
1262	669	in	15	Compra fornecedor	2026-01-12 02:32:16.434
1263	669	in	8	Venda	2026-04-30 18:27:25.081
1264	670	in	13	Venda	2026-04-16 13:15:03.476
1265	671	in	17	Venda	2026-05-17 19:16:56.734
1266	671	in	13	Reposição	2026-05-05 08:10:37.404
1267	672	out	9	Ajuste inventário	2025-12-12 19:02:23.364
1268	672	in	17	Compra fornecedor	2026-01-02 04:27:36.046
1269	673	in	6	Ajuste inventário	2026-03-24 03:15:06.075
1270	673	out	11	Ajuste inventário	2026-04-17 19:24:58.408
1271	674	out	18	Ajuste inventário	2026-02-12 04:10:13.164
1272	674	in	13	Compra fornecedor	2026-03-06 18:55:01.607
1273	675	in	6	Devolução	2026-01-21 05:54:34.339
1274	675	out	13	Compra fornecedor	2026-05-21 23:24:37.69
1275	675	in	20	Compra fornecedor	2026-01-20 01:29:03.119
1276	676	in	15	Devolução	2026-04-30 13:07:13.431
1277	677	in	14	Ajuste inventário	2026-04-12 11:48:19.846
1278	678	in	16	Devolução	2026-04-04 14:36:17.307
1279	678	in	6	Venda	2026-01-23 04:28:44.669
1280	679	out	13	Ajuste inventário	2026-01-12 22:20:39.701
1281	680	in	16	Reposição	2026-04-18 03:32:34.243
1282	680	out	14	Venda	2026-01-08 17:25:00.809
1283	680	in	1	Devolução	2026-01-21 01:07:30.352
1284	681	in	10	Reposição	2026-01-16 00:18:17.572
1285	681	out	16	Venda	2026-03-06 04:32:44.07
1286	681	in	16	Devolução	2026-03-01 10:28:57.829
1287	682	in	16	Reposição	2026-05-16 22:30:52.134
1288	682	out	9	Reposição	2026-02-11 02:56:49.257
1289	683	in	20	Devolução	2026-04-23 03:24:05.783
1290	683	in	16	Devolução	2026-04-07 15:17:01.076
1291	684	in	3	Ajuste inventário	2026-01-16 07:50:12.364
1292	685	in	5	Compra fornecedor	2026-05-24 18:45:00.832
1293	686	in	11	Devolução	2026-05-25 03:46:02.272
1294	686	in	6	Reposição	2026-02-09 12:38:24.069
1295	687	in	1	Reposição	2026-01-22 23:39:03.857
1296	688	out	12	Compra fornecedor	2025-12-16 12:03:28.204
1297	688	in	9	Devolução	2026-02-22 09:08:45.644
1298	688	out	11	Devolução	2026-05-20 07:58:22.236
1299	689	in	3	Compra fornecedor	2026-03-08 09:22:58.401
1300	690	in	20	Compra fornecedor	2026-03-13 18:06:10.954
1301	691	in	11	Reposição	2026-02-13 08:00:02.48
1302	692	in	3	Venda	2026-03-28 10:29:35.67
1303	693	in	13	Ajuste inventário	2025-12-04 15:12:58.171
1304	694	in	16	Venda	2026-03-01 06:04:35.083
1305	694	in	7	Compra fornecedor	2026-02-07 09:41:43.716
1306	694	out	14	Compra fornecedor	2026-03-23 07:40:00.556
1307	695	out	3	Reposição	2026-01-27 07:02:26.522
1308	695	in	11	Reposição	2026-05-27 00:07:48.641
1309	695	out	1	Reposição	2025-12-11 08:00:16.433
1310	696	in	10	Devolução	2026-03-02 02:16:29.291
1311	697	in	6	Reposição	2025-12-15 13:55:55.857
1312	697	out	14	Ajuste inventário	2026-04-11 21:41:50.523
1313	697	in	18	Compra fornecedor	2026-02-15 03:42:17.086
1314	698	in	14	Reposição	2026-04-20 11:22:22.992
1315	699	out	10	Ajuste inventário	2026-03-24 06:12:33.43
1316	699	in	17	Compra fornecedor	2026-03-16 10:04:49.397
1317	700	out	18	Ajuste inventário	2026-04-02 04:48:58.382
1318	700	in	10	Reposição	2026-05-26 20:00:36.753
1319	701	in	18	Reposição	2026-02-07 15:17:54.986
1320	701	in	16	Ajuste inventário	2026-06-07 18:17:05.493
1321	701	in	15	Devolução	2026-03-04 21:05:52.425
1322	702	in	9	Compra fornecedor	2026-02-13 17:57:57.269
1323	702	out	19	Venda	2026-02-06 11:52:26.252
1324	702	in	14	Reposição	2026-04-01 18:44:31.641
1325	703	in	2	Devolução	2026-03-25 09:20:45.307
1326	703	out	18	Devolução	2026-04-28 08:58:24.78
1327	704	out	12	Compra fornecedor	2026-02-26 05:37:56.566
1328	704	out	1	Compra fornecedor	2025-12-13 18:14:22.155
1329	704	out	11	Venda	2025-12-21 01:36:49.415
1330	705	in	6	Devolução	2026-03-17 05:05:22.813
1331	705	in	13	Venda	2026-05-01 00:25:33.575
1332	706	in	16	Devolução	2026-01-04 16:50:01.425
1333	707	out	16	Venda	2026-04-05 01:22:48.653
1334	708	in	1	Venda	2025-12-15 05:16:59.757
1335	709	in	9	Compra fornecedor	2026-02-07 16:58:13.858
1336	709	out	8	Devolução	2026-02-09 04:49:22.727
1337	710	in	20	Compra fornecedor	2025-12-07 06:05:12.426
1338	710	out	19	Reposição	2026-03-02 23:47:20.285
1339	711	out	12	Devolução	2026-05-16 01:26:14.57
1340	711	out	10	Ajuste inventário	2026-04-01 12:35:02.304
1341	712	in	1	Compra fornecedor	2026-03-03 19:37:19.914
1342	712	out	6	Ajuste inventário	2026-02-04 13:01:37.583
1343	713	out	18	Compra fornecedor	2026-04-16 18:13:47.701
1344	714	out	7	Venda	2026-03-18 21:34:51.241
1345	715	in	15	Compra fornecedor	2026-05-24 14:20:32.743
1346	715	in	19	Ajuste inventário	2026-02-24 03:17:43.708
1347	715	out	20	Devolução	2025-12-25 03:39:50.295
1348	716	in	11	Ajuste inventário	2025-12-04 13:23:04.901
1349	716	out	15	Compra fornecedor	2026-03-19 08:17:30.687
1350	717	out	2	Devolução	2026-01-23 08:13:44.023
1351	717	in	16	Devolução	2025-12-23 14:11:51.938
1352	718	out	4	Reposição	2026-04-13 11:37:09.291
1353	718	out	6	Venda	2026-05-22 03:26:55.386
1354	719	in	13	Compra fornecedor	2026-05-01 08:28:43.899
1355	720	out	16	Compra fornecedor	2026-02-11 09:40:56.224
1356	720	out	9	Reposição	2026-04-19 18:58:35.226
1357	721	out	3	Compra fornecedor	2026-04-19 13:17:07.249
1358	722	in	6	Venda	2026-02-04 03:34:31.234
1359	722	in	5	Devolução	2026-05-21 01:50:53.71
1360	722	in	4	Reposição	2026-04-20 22:31:55.16
1361	723	in	3	Ajuste inventário	2026-03-27 17:49:02.878
1362	723	in	12	Compra fornecedor	2026-03-02 03:02:19.388
1363	723	out	9	Devolução	2026-02-24 17:25:56.062
1364	724	in	9	Compra fornecedor	2026-04-07 00:28:28.673
1365	725	in	1	Reposição	2026-01-20 02:27:50.561
1366	725	in	8	Devolução	2026-01-25 20:15:34.854
1367	725	in	9	Compra fornecedor	2026-02-01 18:06:31.597
1368	726	out	3	Compra fornecedor	2026-04-01 17:44:38.827
1369	726	out	7	Ajuste inventário	2026-01-02 10:08:05.153
1370	727	in	16	Ajuste inventário	2026-05-05 01:31:57.417
1371	728	out	6	Compra fornecedor	2026-06-03 15:53:23.687
1372	728	out	17	Compra fornecedor	2026-02-06 08:20:41.959
1373	729	in	12	Ajuste inventário	2025-12-04 08:19:52.581
1374	729	in	6	Compra fornecedor	2026-03-30 23:48:29.91
1375	730	in	18	Ajuste inventário	2026-02-13 12:06:15.661
1376	731	out	1	Ajuste inventário	2026-03-27 01:09:46.741
1377	731	in	16	Reposição	2026-05-29 06:01:43.645
1378	732	in	20	Ajuste inventário	2026-01-09 13:50:15.422
1379	733	in	6	Reposição	2025-12-31 20:54:17.781
1380	733	in	6	Devolução	2025-12-24 09:16:50.201
1381	734	out	17	Venda	2026-05-05 07:05:57.245
1382	734	in	14	Ajuste inventário	2025-12-22 18:56:47.275
1383	735	in	4	Venda	2026-04-04 03:00:12.658
1384	735	in	4	Compra fornecedor	2026-02-28 14:41:33.082
1385	736	in	2	Ajuste inventário	2026-04-29 18:12:55.104
1386	736	out	18	Compra fornecedor	2026-06-02 14:52:19.505
1387	737	out	6	Ajuste inventário	2026-02-06 05:54:36.739
1388	738	out	15	Reposição	2026-03-27 13:37:37.032
1389	739	in	20	Ajuste inventário	2026-04-13 02:10:38.143
1390	739	in	11	Reposição	2026-01-01 14:52:21.493
1391	740	in	16	Compra fornecedor	2025-12-16 12:14:25.164
1392	741	in	9	Compra fornecedor	2026-05-31 22:09:41.414
1393	742	in	15	Ajuste inventário	2026-01-15 02:53:37.425
1394	742	in	10	Ajuste inventário	2026-01-25 08:00:20.652
1395	742	out	10	Devolução	2026-01-05 23:05:13.778
1396	743	in	11	Devolução	2026-04-26 02:14:39.257
1397	743	in	14	Reposição	2026-03-29 21:03:07.72
1398	744	out	3	Reposição	2026-03-09 03:58:18.699
1399	745	in	8	Reposição	2025-12-04 23:40:56.867
1400	746	out	8	Ajuste inventário	2026-03-20 22:14:01.866
1401	746	in	4	Compra fornecedor	2026-03-26 20:44:28.177
1402	747	in	5	Venda	2026-05-03 15:51:52.432
1403	747	in	18	Compra fornecedor	2026-05-28 18:45:43.895
1404	747	in	14	Venda	2026-04-28 13:53:38.191
1405	748	in	8	Reposição	2026-04-23 10:27:58.95
1406	749	in	3	Reposição	2026-04-29 12:32:10.156
1407	749	out	10	Reposição	2026-05-17 00:23:08.851
1408	750	in	13	Ajuste inventário	2026-02-13 21:44:36.472
1409	750	in	9	Ajuste inventário	2026-02-20 08:17:41.611
1410	751	out	11	Compra fornecedor	2026-02-08 23:31:23.756
1411	752	out	7	Reposição	2025-12-15 13:18:33.343
1412	752	out	5	Compra fornecedor	2026-02-21 10:09:52.727
1413	752	in	11	Devolução	2026-05-10 01:29:04.048
1414	753	in	3	Compra fornecedor	2026-04-01 19:56:25.28
1415	753	in	15	Ajuste inventário	2026-01-07 17:32:18.17
1416	754	in	9	Devolução	2026-02-26 18:21:07.121
1417	754	in	15	Compra fornecedor	2026-04-20 07:47:14.738
1418	755	in	18	Devolução	2025-12-07 06:04:23.642
1419	755	in	18	Compra fornecedor	2026-03-14 14:21:20.574
1420	756	out	16	Devolução	2026-04-11 11:39:35.892
1421	756	out	13	Ajuste inventário	2026-02-28 15:54:19.948
1422	757	out	6	Venda	2026-05-26 20:10:17.931
1423	757	in	4	Devolução	2026-06-07 05:52:31.546
1424	758	out	5	Reposição	2026-03-10 21:35:49.656
1425	758	out	7	Compra fornecedor	2026-03-01 10:27:01.501
1426	758	in	15	Reposição	2026-04-11 06:50:31.665
1427	759	in	16	Reposição	2026-04-15 01:35:34.303
1428	759	in	13	Devolução	2026-01-18 02:03:53.563
1429	759	out	20	Ajuste inventário	2026-04-13 04:51:58.878
1430	760	out	11	Reposição	2026-02-24 07:06:20.859
1431	760	in	17	Devolução	2026-05-11 08:37:09.613
1432	761	in	19	Compra fornecedor	2026-05-03 20:00:52.684
1433	762	out	3	Devolução	2026-05-18 22:14:05.352
1434	762	in	9	Ajuste inventário	2025-12-16 15:09:35.357
1435	762	out	18	Reposição	2026-03-22 04:26:06.451
1436	763	in	14	Devolução	2026-05-21 05:30:42.608
1437	763	out	19	Reposição	2026-05-15 01:14:38.979
1438	764	out	13	Venda	2025-12-11 17:42:24.074
1439	765	in	10	Devolução	2026-05-23 05:41:30.964
1440	765	out	10	Venda	2026-01-15 13:23:44.193
1441	766	in	20	Ajuste inventário	2025-12-25 06:47:40.715
1442	767	in	11	Compra fornecedor	2026-05-30 15:50:06.418
1443	768	in	2	Ajuste inventário	2025-12-27 04:18:07.107
1444	769	in	13	Compra fornecedor	2026-01-29 12:46:29.692
1445	770	in	11	Compra fornecedor	2025-12-09 20:07:27.636
1446	770	in	5	Compra fornecedor	2026-02-19 13:02:29.036
1447	771	out	17	Reposição	2026-06-03 19:10:57.003
1448	771	out	13	Venda	2026-01-04 12:17:35.371
1449	771	out	20	Ajuste inventário	2026-04-17 11:58:40.507
1450	772	in	9	Ajuste inventário	2026-02-08 17:02:39.185
1451	772	out	18	Reposição	2026-01-13 06:18:22.079
1452	773	in	7	Devolução	2026-01-27 21:24:55.119
1453	773	in	8	Devolução	2026-02-01 02:55:49.427
1454	773	out	14	Devolução	2026-05-20 10:54:53.735
1455	774	in	7	Ajuste inventário	2026-04-15 15:20:42.361
1456	774	in	7	Devolução	2026-04-07 11:06:40.058
1457	775	out	16	Devolução	2026-02-22 12:51:23.715
1458	775	out	12	Venda	2026-01-25 15:13:35.829
1459	776	out	4	Compra fornecedor	2026-05-17 11:46:53.685
1460	776	out	6	Venda	2026-04-05 10:27:26.167
1461	777	out	3	Compra fornecedor	2026-01-09 14:41:49.57
1462	778	in	2	Devolução	2026-01-01 05:06:04.106
1463	779	in	14	Venda	2026-01-15 15:52:18.567
1464	779	in	12	Devolução	2026-04-23 23:37:43.227
1465	779	out	9	Reposição	2026-03-29 06:57:28.496
1466	780	out	1	Venda	2026-03-19 15:45:11.762
1467	780	out	12	Devolução	2026-01-23 16:54:35.195
1468	780	in	2	Ajuste inventário	2026-04-10 20:00:49.732
1469	781	out	2	Compra fornecedor	2026-04-13 08:00:06.342
1470	782	out	17	Reposição	2026-01-02 17:05:04.068
1471	783	out	16	Devolução	2026-01-13 08:26:34.961
1472	783	in	12	Devolução	2026-01-30 15:16:34.287
1473	784	out	6	Compra fornecedor	2025-12-29 01:37:09.442
1474	785	in	8	Compra fornecedor	2025-12-19 09:54:08.863
1475	786	out	2	Ajuste inventário	2025-12-23 18:40:46.455
1476	787	in	2	Devolução	2026-02-27 01:07:12.634
1477	788	in	3	Venda	2026-04-25 12:20:56.042
1478	788	in	9	Venda	2025-12-16 05:49:21.974
1479	788	out	11	Devolução	2026-04-05 02:06:30.025
1480	789	in	13	Compra fornecedor	2026-02-17 17:35:14.108
1481	789	out	16	Devolução	2026-04-07 14:11:34.413
1482	790	in	1	Devolução	2026-05-30 23:47:31.47
1483	791	in	10	Reposição	2026-03-15 21:00:08.39
1484	792	out	17	Compra fornecedor	2026-05-25 03:23:51.971
1485	793	in	10	Reposição	2026-04-05 07:13:38.399
1486	793	in	20	Compra fornecedor	2026-04-21 15:47:23.496
1487	794	in	4	Reposição	2026-02-18 17:48:31.864
1488	794	out	11	Devolução	2026-03-02 01:20:42.829
1489	795	in	18	Ajuste inventário	2026-01-10 13:19:44.238
1490	796	out	2	Reposição	2026-04-12 00:51:56.649
1491	796	in	5	Devolução	2026-04-28 03:42:37.484
1492	796	in	6	Venda	2026-03-24 14:57:49.477
\.


--
-- Data for Name: User; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."User" (id, email, "displayName", role, "acceptedTerms", "createdAt") FROM stdin;
user_001	ana laura.braga0@email.com	Ana Laura Braga	admin	t	2026-06-10 13:39:56.096
user_002	maria cecília.silva1@email.com	Maria Cecília Silva	admin	t	2026-06-10 13:39:56.099
user_003	maria helena.albuquerque2@email.com	Maria Helena Albuquerque	customer	t	2026-06-10 13:39:56.1
user_004	felícia.batista3@email.com	Felícia Batista	customer	t	2026-06-10 13:39:56.1
user_005	eduarda.pereira4@email.com	Eduarda Pereira	customer	t	2026-06-10 13:39:56.101
user_006	mércia.silva5@email.com	Mércia Silva	customer	t	2026-06-10 13:39:56.102
user_007	benjamin.reis6@email.com	Benjamin Reis	customer	t	2026-06-10 13:39:56.102
user_008	eduarda.nogueira7@email.com	Eduarda Nogueira	customer	t	2026-06-10 13:39:56.103
user_009	larissa.costa8@email.com	Larissa Costa	customer	t	2026-06-10 13:39:56.103
user_010	théo.batista9@email.com	Théo Batista	customer	t	2026-06-10 13:39:56.104
user_011	luiza.macedo10@email.com	Luiza Macedo	customer	t	2026-06-10 13:39:56.104
user_012	isabel.batista11@email.com	Isabel Batista	customer	t	2026-06-10 13:39:56.105
user_013	lorenzo.moraes12@email.com	Lorenzo Moraes	customer	t	2026-06-10 13:39:56.105
user_014	luiza.melo13@email.com	Luiza Melo	customer	t	2026-06-10 13:39:56.106
user_015	felícia.moreira14@email.com	Felícia Moreira	customer	t	2026-06-10 13:39:56.106
user_016	vitória.batista15@email.com	Vitória Batista	customer	t	2026-06-10 13:39:56.107
user_017	emanuelly.costa16@email.com	Emanuelly Costa	customer	t	2026-06-10 13:39:56.107
user_018	sara.martins17@email.com	Sara Martins	customer	t	2026-06-10 13:39:56.108
user_019	bryan.silva18@email.com	Bryan Silva	customer	t	2026-06-10 13:39:56.108
user_020	emanuel.souza19@email.com	Emanuel Souza	customer	t	2026-06-10 13:39:56.109
user_021	ladislau.braga20@email.com	Ladislau Braga	customer	t	2026-06-10 13:39:56.109
user_022	júlia.batista21@email.com	Júlia Batista	customer	t	2026-06-10 13:39:56.109
user_023	fabiano.moraes22@email.com	Fabiano Moraes	customer	t	2026-06-10 13:39:56.11
user_024	arthur.barros23@email.com	Arthur Barros	customer	t	2026-06-10 13:39:56.11
user_025	felipe.pereira24@email.com	Felipe Pereira	customer	t	2026-06-10 13:39:56.111
user_026	lorenzo.macedo25@email.com	Lorenzo Macedo	customer	t	2026-06-10 13:39:56.111
user_027	salvador.reis26@email.com	Salvador Reis	customer	t	2026-06-10 13:39:56.112
user_028	daniel.nogueira27@email.com	Daniel Nogueira	customer	t	2026-06-10 13:39:56.112
user_029	carlos.braga28@email.com	Carlos Braga	customer	t	2026-06-10 13:39:56.113
user_030	natália.macedo29@email.com	Natália Macedo	customer	t	2026-06-10 13:39:56.113
user_031	guilherme.macedo30@email.com	Guilherme Macedo	customer	t	2026-06-10 13:39:56.113
user_032	helena.carvalho31@email.com	Helena Carvalho	customer	t	2026-06-10 13:39:56.114
user_033	gael.oliveira32@email.com	Gael Oliveira	customer	t	2026-06-10 13:39:56.114
user_034	sílvia.batista33@email.com	Sílvia Batista	customer	t	2026-06-10 13:39:56.115
user_035	lucca.santos34@email.com	Lucca Santos	customer	t	2026-06-10 13:39:56.115
user_036	heloísa.albuquerque35@email.com	Heloísa Albuquerque	customer	t	2026-06-10 13:39:56.115
user_037	pedro henrique.saraiva36@email.com	Pedro Henrique Saraiva	customer	t	2026-06-10 13:39:56.116
user_038	paula.santos37@email.com	Paula Santos	customer	t	2026-06-10 13:39:56.116
user_039	eloá.oliveira38@email.com	Eloá Oliveira	customer	t	2026-06-10 13:39:56.117
user_040	júlio.braga39@email.com	Júlio Braga	customer	t	2026-06-10 13:39:56.117
user_041	leonardo.souza40@email.com	Leonardo Souza	customer	t	2026-06-10 13:39:56.117
user_042	marcela.albuquerque41@email.com	Marcela Albuquerque	customer	t	2026-06-10 13:39:56.118
user_043	warley.souza42@email.com	Warley Souza	customer	t	2026-06-10 13:39:56.119
user_044	cauã.martins43@email.com	Cauã Martins	customer	t	2026-06-10 13:39:56.119
user_045	warley.batista44@email.com	Warley Batista	customer	t	2026-06-10 13:39:56.119
user_046	salvador.silva45@email.com	Salvador Silva	customer	t	2026-06-10 13:39:56.12
user_047	lorenzo.macedo46@email.com	Lorenzo Macedo	customer	t	2026-06-10 13:39:56.12
user_048	alessandro.moreira47@email.com	Alessandro Moreira	customer	t	2026-06-10 13:39:56.121
user_049	fábio.melo48@email.com	Fábio Melo	customer	t	2026-06-10 13:39:56.121
user_050	lara.moraes49@email.com	Lara Moraes	customer	t	2026-06-10 13:39:56.122
user_051	sophia.oliveira50@email.com	Sophia Oliveira	customer	t	2026-06-10 13:39:56.122
user_052	maria eduarda.braga51@email.com	Maria Eduarda Braga	customer	t	2026-06-10 13:39:56.123
user_053	ana laura.nogueira52@email.com	Ana Laura Nogueira	customer	t	2026-06-10 13:39:56.123
user_054	meire.carvalho53@email.com	Meire Carvalho	customer	t	2026-06-10 13:39:56.124
user_055	aline.barros54@email.com	Aline Barros	customer	t	2026-06-10 13:39:56.124
user_056	hugo.martins55@email.com	Hugo Martins	customer	t	2026-06-10 13:39:56.125
user_057	cauã.souza56@email.com	Cauã Souza	customer	t	2026-06-10 13:39:56.125
user_058	fabrícia.albuquerque57@email.com	Fabrícia Albuquerque	customer	t	2026-06-10 13:39:56.126
user_059	mariana.carvalho58@email.com	Mariana Carvalho	customer	t	2026-06-10 13:39:56.127
user_060	maria helena.santos59@email.com	Maria Helena Santos	customer	t	2026-06-10 13:39:56.127
user_061	maria clara.costa60@email.com	Maria Clara Costa	customer	t	2026-06-10 13:39:56.128
user_062	silas.pereira61@email.com	Silas Pereira	customer	t	2026-06-10 13:39:56.128
user_063	giovanna.barros62@email.com	Giovanna Barros	customer	t	2026-06-10 13:39:56.129
user_064	aline.martins63@email.com	Aline Martins	customer	t	2026-06-10 13:39:56.129
user_065	ricardo.macedo64@email.com	Ricardo Macedo	customer	t	2026-06-10 13:39:56.13
user_066	enzo.moreira65@email.com	Enzo Moreira	customer	t	2026-06-10 13:39:56.13
user_067	giovanna.batista66@email.com	Giovanna Batista	customer	t	2026-06-10 13:39:56.13
user_068	joaquim.martins67@email.com	Joaquim Martins	customer	t	2026-06-10 13:39:56.131
user_069	fabrícia.costa68@email.com	Fabrícia Costa	customer	t	2026-06-10 13:39:56.132
user_070	ofélia.braga69@email.com	Ofélia Braga	customer	t	2026-06-10 13:39:56.132
user_071	alice.nogueira70@email.com	Alice Nogueira	customer	t	2026-06-10 13:39:56.133
user_072	lívia.carvalho71@email.com	Lívia Carvalho	customer	t	2026-06-10 13:39:56.133
user_073	carla.nogueira72@email.com	Carla Nogueira	customer	t	2026-06-10 13:39:56.134
user_074	miguel.martins73@email.com	Miguel Martins	customer	t	2026-06-10 13:39:56.134
user_075	lorraine.reis74@email.com	Lorraine Reis	customer	t	2026-06-10 13:39:56.135
user_076	margarida.franco75@email.com	Margarida Franco	customer	t	2026-06-10 13:39:56.135
user_077	marina.melo76@email.com	Marina Melo	customer	t	2026-06-10 13:39:56.136
user_078	warley.albuquerque77@email.com	Warley Albuquerque	customer	t	2026-06-10 13:39:56.136
user_079	margarida.nogueira78@email.com	Margarida Nogueira	customer	t	2026-06-10 13:39:56.136
user_080	morgana.reis79@email.com	Morgana Reis	customer	t	2026-06-10 13:39:56.137
user_081	maria júlia.saraiva80@email.com	Maria Júlia Saraiva	customer	t	2026-06-10 13:39:56.138
user_082	nicolas.macedo81@email.com	Nicolas Macedo	customer	t	2026-06-10 13:39:56.138
user_083	sophia.melo82@email.com	Sophia Melo	customer	t	2026-06-10 13:39:56.139
user_084	luiza.santos83@email.com	Luiza Santos	customer	t	2026-06-10 13:39:56.139
user_085	nataniel.moraes84@email.com	Nataniel Moraes	customer	t	2026-06-10 13:39:56.14
user_086	yasmin.pereira85@email.com	Yasmin Pereira	customer	t	2026-06-10 13:39:56.14
user_087	daniel.albuquerque86@email.com	Daniel Albuquerque	customer	t	2026-06-10 13:39:56.14
user_088	fabrício.souza87@email.com	Fabrício Souza	customer	t	2026-06-10 13:39:56.141
user_089	rafaela.saraiva88@email.com	Rafaela Saraiva	customer	t	2026-06-10 13:39:56.141
user_090	margarida.barros89@email.com	Margarida Barros	customer	t	2026-06-10 13:39:56.142
user_091	frederico.franco90@email.com	Frederico Franco	customer	t	2026-06-10 13:39:56.143
user_092	rafael.silva91@email.com	Rafael Silva	customer	t	2026-06-10 13:39:56.143
user_093	eduardo.albuquerque92@email.com	Eduardo Albuquerque	customer	t	2026-06-10 13:39:56.144
user_094	joão pedro.xavier93@email.com	João Pedro Xavier	customer	t	2026-06-10 13:39:56.144
user_095	morgana.oliveira94@email.com	Morgana Oliveira	customer	t	2026-06-10 13:39:56.145
user_096	yuri.martins95@email.com	Yuri Martins	customer	t	2026-06-10 13:39:56.145
user_097	elísio.franco96@email.com	Elísio Franco	customer	t	2026-06-10 13:39:56.145
user_098	eloá.xavier97@email.com	Eloá Xavier	customer	t	2026-06-10 13:39:56.146
user_099	isis.souza98@email.com	Isis Souza	customer	t	2026-06-10 13:39:56.146
user_100	bernardo.souza99@email.com	Bernardo Souza	customer	t	2026-06-10 13:39:56.147
user_101	maria.carvalho100@email.com	Maria Carvalho	customer	t	2026-06-10 13:39:56.147
user_102	matheus.carvalho101@email.com	Matheus Carvalho	customer	t	2026-06-10 13:39:56.148
user_103	elisa.macedo102@email.com	Elisa Macedo	customer	t	2026-06-10 13:39:56.148
user_104	valentina.xavier103@email.com	Valentina Xavier	customer	t	2026-06-10 13:39:56.148
user_105	janaína.braga104@email.com	Janaína Braga	customer	t	2026-06-10 13:39:56.149
user_106	deneval.nogueira105@email.com	Deneval Nogueira	customer	t	2026-06-10 13:39:56.149
user_107	breno.batista106@email.com	Breno Batista	customer	t	2026-06-10 13:39:56.15
user_108	yago.oliveira107@email.com	Yago Oliveira	customer	t	2026-06-10 13:39:56.15
user_109	bernardo.costa108@email.com	Bernardo Costa	customer	t	2026-06-10 13:39:56.151
user_110	joão.pereira109@email.com	João Pereira	customer	t	2026-06-10 13:39:56.151
user_111	paula.nogueira110@email.com	Paula Nogueira	customer	t	2026-06-10 13:39:56.152
user_112	fábio.costa111@email.com	Fábio Costa	customer	t	2026-06-10 13:39:56.152
user_113	raul.silva112@email.com	Raul Silva	customer	t	2026-06-10 13:39:56.153
user_114	salvador.nogueira113@email.com	Salvador Nogueira	customer	t	2026-06-10 13:39:56.153
user_115	cauã.albuquerque114@email.com	Cauã Albuquerque	customer	t	2026-06-10 13:39:56.153
user_116	calebe.braga115@email.com	Calebe Braga	customer	t	2026-06-10 13:39:56.154
user_117	salvador.franco116@email.com	Salvador Franco	customer	t	2026-06-10 13:39:56.154
user_118	yuri.oliveira117@email.com	Yuri Oliveira	customer	t	2026-06-10 13:39:56.155
user_119	pietro.moreira118@email.com	Pietro Moreira	customer	t	2026-06-10 13:39:56.155
user_120	fábio.batista119@email.com	Fábio Batista	customer	t	2026-06-10 13:39:56.156
\.


--
-- Data for Name: Wishlist; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Wishlist" (id, "userId", "productId", "createdAt") FROM stdin;
cmq848j9x013vlz651yioqnf1	user_025	cmq848ii0001glz65zwwuce61	2026-06-10 13:39:56.949
cmq848ja1013xlz65z8n5na95	user_059	cmq848il40054lz65pt2vtbp1	2026-06-10 13:39:56.953
cmq848ja3013zlz659xhovasd	user_069	cmq848ilo005qlz657qbcleae	2026-06-10 13:39:56.955
cmq848ja40141lz65aemcbnfg	user_077	cmq848ikk004ilz65atys1fdm	2026-06-10 13:39:56.957
cmq848ja60143lz652bswvksu	user_081	cmq848ijc0030lz65k5f1ruxs	2026-06-10 13:39:56.958
cmq848ja70145lz65xnj8bzsn	user_083	cmq848ih8000qlz6575344eyf	2026-06-10 13:39:56.96
cmq848ja80147lz65ucu8p3dk	user_104	cmq848il00050lz65jly7d3ls	2026-06-10 13:39:56.96
cmq848ja90149lz65j24tchvv	user_030	cmq848iky004ylz65gaaevnn2	2026-06-10 13:39:56.962
cmq848jaa014blz65vwh482jo	user_002	cmq848ii5001mlz6549m4ra8a	2026-06-10 13:39:56.962
cmq848jab014dlz65lnxwkb6u	user_008	cmq848il20052lz6542nm8a9p	2026-06-10 13:39:56.963
cmq848jab014flz657pd2997h	user_091	cmq848il70058lz65kvskyjj0	2026-06-10 13:39:56.964
cmq848jac014hlz65l7ncwlaa	user_001	cmq848ijo003clz65wfuym48q	2026-06-10 13:39:56.964
cmq848jac014jlz65vbna498c	user_085	cmq848iht0018lz65i6s6humm	2026-06-10 13:39:56.965
cmq848jad014llz65vemm02f4	user_078	cmq848ihc000ulz65um9y1gnx	2026-06-10 13:39:56.965
cmq848jad014nlz65bh66a9gr	user_022	cmq848ijh0036lz65wsfy2t1j	2026-06-10 13:39:56.966
cmq848jae014plz65u8gtian6	user_079	cmq848ihq0016lz65zw3mbwpe	2026-06-10 13:39:56.966
cmq848jaf014rlz65z9xw7u76	user_023	cmq848ii3001klz65yorar9lb	2026-06-10 13:39:56.967
cmq848jaf014tlz653dt7fm7y	user_029	cmq848ii6001olz65adf9giip	2026-06-10 13:39:56.968
cmq848jag014vlz65gsct1lt9	user_048	cmq848ike004alz65zfska0qx	2026-06-10 13:39:56.968
cmq848jah014xlz65gwghhbr7	user_053	cmq848il00050lz65jly7d3ls	2026-06-10 13:39:56.969
cmq848jai014zlz65pyst9mau	user_087	cmq848ihj0012lz655nqbfi4h	2026-06-10 13:39:56.97
cmq848jaj0151lz65jz2cnu6c	user_006	cmq848ilk005mlz65s3sdjsu8	2026-06-10 13:39:56.971
cmq848jaj0153lz655b29lo7g	user_010	cmq848iht0018lz65i6s6humm	2026-06-10 13:39:56.972
cmq848jal0155lz655eq65wdl	user_003	cmq848ik90044lz65z6mok81k	2026-06-10 13:39:56.973
cmq848jam0157lz65mvq7v1hk	user_070	cmq848im4006alz65yqqlc42q	2026-06-10 13:39:56.974
cmq848jam0159lz65uaipq064	user_107	cmq848ij6002slz650iblsiyq	2026-06-10 13:39:56.975
cmq848jan015blz65wu7t23gy	user_045	cmq848iim0024lz653bqj3pmx	2026-06-10 13:39:56.975
cmq848jan015dlz65s5jr64w6	user_019	cmq848ihq0016lz65zw3mbwpe	2026-06-10 13:39:56.976
cmq848jan015flz65m7zr49ct	user_016	cmq848ihh0010lz65up1lvi82	2026-06-10 13:39:56.976
cmq848jao015hlz65e9uz10jx	user_029	cmq848iio0026lz65jq33hxb7	2026-06-10 13:39:56.976
cmq848jao015jlz65y0rl5e6y	user_116	cmq848ik1003ulz653oni9m29	2026-06-10 13:39:56.977
cmq848jap015llz65j7637c7c	user_119	cmq848ij0002klz65fxbxd314	2026-06-10 13:39:56.977
cmq848jap015nlz65r9i2tglj	user_055	cmq848iit002alz65y173ku0u	2026-06-10 13:39:56.978
cmq848jaq015plz65axpv4hqa	user_022	cmq848ihq0016lz65zw3mbwpe	2026-06-10 13:39:56.978
cmq848jaq015rlz65fv4vbnup	user_114	cmq848im4006alz65yqqlc42q	2026-06-10 13:39:56.979
cmq848jar015tlz65sotgput4	user_006	cmq848iht0018lz65i6s6humm	2026-06-10 13:39:56.979
cmq848jar015vlz65vyj56apm	user_051	cmq848ii0001glz65zwwuce61	2026-06-10 13:39:56.98
cmq848jar015xlz655bujhkuk	user_044	cmq848ihm0014lz65xbhdl0sk	2026-06-10 13:39:56.98
cmq848jas015zlz65gobibv40	user_055	cmq848iig001ylz65bxct2alm	2026-06-10 13:39:56.98
cmq848jas0161lz65dsmv19yv	user_043	cmq848ihe000wlz65o8uu03fy	2026-06-10 13:39:56.981
cmq848jat0163lz65bhfrbz5u	user_052	cmq848im4006alz65yqqlc42q	2026-06-10 13:39:56.981
cmq848jat0165lz65no1ambve	user_040	cmq848ilk005mlz65s3sdjsu8	2026-06-10 13:39:56.982
cmq848jau0167lz65ovzq1l1h	user_102	cmq848ily0062lz65yremo0se	2026-06-10 13:39:56.982
cmq848jav0169lz65ha7l1m2r	user_095	cmq848ike004alz65zfska0qx	2026-06-10 13:39:56.983
cmq848jav016blz65103qkyl1	user_103	cmq848iha000slz65x7kqdxj9	2026-06-10 13:39:56.984
cmq848jaw016dlz65bkhxje0j	user_056	cmq848im4006alz65yqqlc42q	2026-06-10 13:39:56.984
cmq848jaw016flz65v32xazv4	user_093	cmq848im00064lz65vvsub73c	2026-06-10 13:39:56.984
cmq848jax016hlz65vxyrv0gi	user_094	cmq848ilk005mlz65s3sdjsu8	2026-06-10 13:39:56.985
cmq848jax016jlz65sz0j8bme	user_085	cmq848ikv004wlz65zp7bsxhi	2026-06-10 13:39:56.986
cmq848jay016llz65tjfmnb3v	user_063	cmq848ilt005wlz65964p7y2x	2026-06-10 13:39:56.987
cmq848jaz016nlz659vgvevoo	user_100	cmq848ilc005elz6582om42hx	2026-06-10 13:39:56.988
cmq848jb0016plz65f5h2id3b	user_081	cmq848iio0026lz65jq33hxb7	2026-06-10 13:39:56.988
cmq848jb0016rlz65derjz97d	user_005	cmq848ilv005ylz65yszzgfgb	2026-06-10 13:39:56.989
cmq848jb1016tlz65pysexxqe	user_071	cmq848iim0024lz653bqj3pmx	2026-06-10 13:39:56.99
cmq848jb2016vlz6504n29i4y	user_018	cmq848ilb005clz65kg0tdzo3	2026-06-10 13:39:56.99
cmq848jb2016xlz65xnwzxnos	user_101	cmq848il70058lz65kvskyjj0	2026-06-10 13:39:56.991
cmq848jb3016zlz65hhlfotpy	user_078	cmq848iiz002ilz65pe7qyt2o	2026-06-10 13:39:56.991
cmq848jb30171lz65dj8047ok	user_037	cmq848igs000clz65lnk7697z	2026-06-10 13:39:56.992
cmq848jb40173lz65441y5v51	user_101	cmq848ihc000ulz65um9y1gnx	2026-06-10 13:39:56.992
cmq848jb40175lz65oxtcm4mp	user_076	cmq848ijo003clz65wfuym48q	2026-06-10 13:39:56.993
cmq848jb50177lz65mt24ovj6	user_064	cmq848ilv005ylz65yszzgfgb	2026-06-10 13:39:56.993
cmq848jb50179lz6504mhcpun	user_004	cmq848il00050lz65jly7d3ls	2026-06-10 13:39:56.994
cmq848jb6017blz650y9whsdw	user_007	cmq848ih4000klz659lkpbiir	2026-06-10 13:39:56.994
cmq848jb6017dlz65bpri2j8a	user_052	cmq848ih7000olz65sykax64r	2026-06-10 13:39:56.995
cmq848jb7017flz65kuwiqnoo	user_095	cmq848ijs003ilz651vofcqoz	2026-06-10 13:39:56.995
cmq848jb7017hlz65eruk8n9u	user_004	cmq848ih4000klz659lkpbiir	2026-06-10 13:39:56.996
cmq848jb8017jlz65ugy2gcsf	user_074	cmq848il60056lz65m1n86f89	2026-06-10 13:39:56.996
cmq848jb9017llz651a6k8paw	user_053	cmq848ijx003olz659ubwcr00	2026-06-10 13:39:56.997
cmq848jb9017nlz65yd8gru5x	user_096	cmq848ik50040lz65iqavat35	2026-06-10 13:39:56.997
cmq848jba017plz65xzcyy456	user_027	cmq848ik50040lz65iqavat35	2026-06-10 13:39:56.998
cmq848jba017rlz65gr0tj3q7	user_076	cmq848iks004slz65ehkzn2hc	2026-06-10 13:39:56.999
cmq848jbb017tlz65oix5hejz	user_075	cmq848im10066lz65y0qob3c4	2026-06-10 13:39:56.999
cmq848jbb017vlz65xqone1oe	user_024	cmq848ily0062lz65yremo0se	2026-06-10 13:39:57
cmq848jbc017xlz65dnu3z4uy	user_065	cmq848iki004elz65yy9n3pwk	2026-06-10 13:39:57.001
cmq848jbd017zlz65upuxphbf	user_012	cmq848ij2002mlz65butp1eug	2026-06-10 13:39:57.001
cmq848jbd0181lz65gu714tbx	user_093	cmq848ikn004mlz65b34aur70	2026-06-10 13:39:57.002
cmq848jbe0183lz65yhiti7o8	user_005	cmq848ijw003mlz653dgdcmdi	2026-06-10 13:39:57.003
cmq848jbf0185lz65o1wgc4hp	user_011	cmq848im5006clz65pzciwfa0	2026-06-10 13:39:57.004
cmq848jbg0187lz65an2cecmk	user_108	cmq848ih0000glz65c18vd6k5	2026-06-10 13:39:57.005
cmq848jbh0189lz65mgk7wpff	user_104	cmq848ilt005wlz65964p7y2x	2026-06-10 13:39:57.006
cmq848jbi018blz65ahawj3zu	user_043	cmq848ikp004olz65mh31wm60	2026-06-10 13:39:57.007
cmq848jbj018dlz65bni5j66m	user_054	cmq848ike004alz65zfska0qx	2026-06-10 13:39:57.008
cmq848jbk018flz65gkyat8ui	user_041	cmq848iit002alz65y173ku0u	2026-06-10 13:39:57.008
cmq848jbk018hlz65a5bnlfn8	user_051	cmq848ihq0016lz65zw3mbwpe	2026-06-10 13:39:57.009
cmq848jbl018jlz65bgt57oft	user_100	cmq848iix002glz659tsuziwu	2026-06-10 13:39:57.009
cmq848jbl018llz65nz8pg6i9	user_049	cmq848ilo005qlz657qbcleae	2026-06-10 13:39:57.01
cmq848jbm018nlz65ucw5ikf5	user_060	cmq848ijw003mlz653dgdcmdi	2026-06-10 13:39:57.01
cmq848jbm018plz65zsoy1h9x	user_115	cmq848iln005olz65hnhu8jjb	2026-06-10 13:39:57.011
cmq848jbn018rlz65qw3yvpqv	user_021	cmq848ijh0036lz65wsfy2t1j	2026-06-10 13:39:57.011
cmq848jbn018tlz65nvme8mno	user_117	cmq848ij0002klz65fxbxd314	2026-06-10 13:39:57.012
cmq848jbo018vlz65hwan44e0	user_045	cmq848ii2001ilz65yyaupzh9	2026-06-10 13:39:57.013
cmq848jbp018xlz658b7s9roe	user_014	cmq848iks004slz65ehkzn2hc	2026-06-10 13:39:57.014
cmq848jbq018zlz65esiq1lkf	user_093	cmq848im10066lz65y0qob3c4	2026-06-10 13:39:57.014
cmq848jbq0191lz654vgnhkbm	user_093	cmq848iia001slz65fc01vzde	2026-06-10 13:39:57.015
cmq848jbr0193lz65s9giezfx	user_005	cmq848im4006alz65yqqlc42q	2026-06-10 13:39:57.015
cmq848jbs0195lz65dfoi0p42	user_041	cmq848iir0028lz65h70y18gn	2026-06-10 13:39:57.016
cmq848jbs0197lz65wpdbjena	user_109	cmq848ik1003ulz653oni9m29	2026-06-10 13:39:57.016
cmq848jbt0199lz656hnu4mkr	user_026	cmq848iln005olz65hnhu8jjb	2026-06-10 13:39:57.017
cmq848jbt019blz65ovfft1n5	user_120	cmq848ihc000ulz65um9y1gnx	2026-06-10 13:39:57.018
cmq848jbu019dlz659o9yqsnq	user_104	cmq848ij3002olz65pe3rcpx3	2026-06-10 13:39:57.018
cmq848jbv019flz65rsrfrlam	user_063	cmq848ils005ulz653byla82q	2026-06-10 13:39:57.019
cmq848jbx019hlz65vq929bo8	user_117	cmq848iie001wlz65u8ntejt8	2026-06-10 13:39:57.021
cmq848jbz019jlz658pefi0e1	user_026	cmq848iha000slz65x7kqdxj9	2026-06-10 13:39:57.023
cmq848jc0019llz652xuofcne	user_068	cmq848igy000elz65szym5a03	2026-06-10 13:39:57.024
cmq848jc1019nlz65gdyh7067	user_050	cmq848ih8000qlz6575344eyf	2026-06-10 13:39:57.026
cmq848jc2019plz65z4898gin	user_049	cmq848ih4000klz659lkpbiir	2026-06-10 13:39:57.027
cmq848jc3019rlz656gzjno3q	user_101	cmq848ii3001klz65yorar9lb	2026-06-10 13:39:57.028
cmq848jc4019tlz655sixtbsb	user_040	cmq848ili005klz65un7jjek4	2026-06-10 13:39:57.029
cmq848jc5019vlz65dbjddibc	user_090	cmq848ii5001mlz6549m4ra8a	2026-06-10 13:39:57.029
cmq848jc5019xlz653w946svc	user_009	cmq848ikp004olz65mh31wm60	2026-06-10 13:39:57.03
cmq848jc6019zlz65gse1djko	user_047	cmq848iky004ylz65gaaevnn2	2026-06-10 13:39:57.03
cmq848jc601a1lz65tvlw7zt4	user_054	cmq848iiw002elz65wl2zq8ty	2026-06-10 13:39:57.031
cmq848jc701a3lz65nqo73p3j	user_055	cmq848ikt004ulz651faf9oi1	2026-06-10 13:39:57.032
cmq848jc801a5lz65q09x3nnd	user_109	cmq848ih5000mlz650gs0sigx	2026-06-10 13:39:57.032
cmq848jc801a7lz659x6n58by	user_063	cmq848ih2000ilz65lyxr140a	2026-06-10 13:39:57.033
cmq848jc901a9lz65hvo7jcmo	user_057	cmq848iln005olz65hnhu8jjb	2026-06-10 13:39:57.033
cmq848jc901ablz655dub4rgd	user_044	cmq848ilv005ylz65yszzgfgb	2026-06-10 13:39:57.034
cmq848jca01adlz65hdnfq5qn	user_076	cmq848ilv005ylz65yszzgfgb	2026-06-10 13:39:57.034
cmq848jcb01aflz65coy7mejg	user_091	cmq848ihf000ylz651yn37u7c	2026-06-10 13:39:57.035
cmq848jcc01ahlz65t4mdm1t6	user_028	cmq848ij3002olz65pe3rcpx3	2026-06-10 13:39:57.036
cmq848jcd01ajlz654vwaq1n2	user_021	cmq848ijm003alz65amc0d44b	2026-06-10 13:39:57.038
cmq848jcf01allz65qcgbluik	user_057	cmq848im00064lz65vvsub73c	2026-06-10 13:39:57.039
cmq848jcg01anlz65iw519o2j	user_053	cmq848il20052lz6542nm8a9p	2026-06-10 13:39:57.04
cmq848jcg01aplz65yr56wp1j	user_114	cmq848ilk005mlz65s3sdjsu8	2026-06-10 13:39:57.041
cmq848jch01arlz65fboukc0r	user_026	cmq848ijo003clz65wfuym48q	2026-06-10 13:39:57.041
cmq848jch01atlz654e6qyv5s	user_042	cmq848ij5002qlz65chlhp8ai	2026-06-10 13:39:57.042
cmq848jci01avlz65ayh01nem	user_044	cmq848ilb005clz65kg0tdzo3	2026-06-10 13:39:57.042
cmq848jci01axlz65kc7exlpy	user_055	cmq848ijs003ilz651vofcqoz	2026-06-10 13:39:57.043
cmq848jcj01azlz65h1h34czb	user_118	cmq848ih7000olz65sykax64r	2026-06-10 13:39:57.043
cmq848jck01b1lz650k0c4lbc	user_059	cmq848il00050lz65jly7d3ls	2026-06-10 13:39:57.044
cmq848jcl01b3lz6594395ikg	user_019	cmq848ik50040lz65iqavat35	2026-06-10 13:39:57.045
cmq848jcl01b5lz65uea8c9ta	user_029	cmq848ili005klz65un7jjek4	2026-06-10 13:39:57.046
cmq848jcm01b7lz65i4rqrr4j	user_040	cmq848iit002alz65y173ku0u	2026-06-10 13:39:57.046
cmq848jcm01b9lz65uwb2f5k7	user_072	cmq848ii0001glz65zwwuce61	2026-06-10 13:39:57.047
cmq848jcn01bblz6533e4eu2j	user_035	cmq848ij8002ulz65bg2e9a8o	2026-06-10 13:39:57.047
cmq848jcn01bdlz65djhi7n99	user_043	cmq848ijs003ilz651vofcqoz	2026-06-10 13:39:57.048
cmq848jco01bflz65cyopjwjx	user_072	cmq848ijz003qlz65dhquij4u	2026-06-10 13:39:57.048
cmq848jco01bhlz65h2utgs2m	user_079	cmq848iio0026lz65jq33hxb7	2026-06-10 13:39:57.049
cmq848jcp01bjlz654iz1u5b2	user_016	cmq848ikv004wlz65zp7bsxhi	2026-06-10 13:39:57.049
cmq848jcp01bllz655rf54zq7	user_103	cmq848iie001wlz65u8ntejt8	2026-06-10 13:39:57.05
cmq848jcq01bnlz65hh6w5mrq	user_049	cmq848ijo003clz65wfuym48q	2026-06-10 13:39:57.05
cmq848jcq01bplz653eq2m81q	user_064	cmq848ike004alz65zfska0qx	2026-06-10 13:39:57.051
cmq848jcr01brlz65q0swfqob	user_005	cmq848ikp004olz65mh31wm60	2026-06-10 13:39:57.051
cmq848jcs01btlz65480pqx6c	user_008	cmq848ijh0036lz65wsfy2t1j	2026-06-10 13:39:57.052
cmq848jct01bvlz658tsjg7ge	user_100	cmq848ije0032lz6553k06x48	2026-06-10 13:39:57.054
cmq848jcu01bxlz65htv7czw2	user_018	cmq848im4006alz65yqqlc42q	2026-06-10 13:39:57.055
cmq848jcv01bzlz65zv91n4rm	user_107	cmq848il00050lz65jly7d3ls	2026-06-10 13:39:57.056
cmq848jcw01c1lz65tt4i40l6	user_050	cmq848ii0001glz65zwwuce61	2026-06-10 13:39:57.056
cmq848jcw01c3lz65vczjd1hh	user_113	cmq848iju003klz655h9g7ycn	2026-06-10 13:39:57.057
cmq848jcx01c5lz654zu7cmvj	user_103	cmq848iiw002elz65wl2zq8ty	2026-06-10 13:39:57.057
cmq848jcx01c7lz65ezbu4bp2	user_041	cmq848im4006alz65yqqlc42q	2026-06-10 13:39:57.058
cmq848jcy01c9lz650n6009tm	user_063	cmq848ihq0016lz65zw3mbwpe	2026-06-10 13:39:57.059
cmq848jcz01cblz65v6tswqhb	user_027	cmq848iji0038lz657sbpyxzb	2026-06-10 13:39:57.059
cmq848jcz01cdlz6520fim03a	user_006	cmq848ijf0034lz65wj1d3jhk	2026-06-10 13:39:57.06
cmq848jd001cflz65ufepe8lx	user_051	cmq848il00050lz65jly7d3ls	2026-06-10 13:39:57.06
cmq848jd001chlz651mxj505j	user_043	cmq848im4006alz65yqqlc42q	2026-06-10 13:39:57.061
cmq848jd101cjlz65gdwz8j2x	user_022	cmq848ik3003wlz6516mr4i90	2026-06-10 13:39:57.061
cmq848jd101cllz650gvh8zsc	user_011	cmq848ikq004qlz65201qbcj6	2026-06-10 13:39:57.062
cmq848jd201cnlz65bdn43tnh	user_120	cmq848il9005alz65fbsfrfd8	2026-06-10 13:39:57.062
cmq848jd201cplz65sfh6vytq	user_067	cmq848iji0038lz657sbpyxzb	2026-06-10 13:39:57.062
cmq848jd301crlz65l4ve1t8t	user_101	cmq848ilw0060lz65kz1v9b1j	2026-06-10 13:39:57.063
cmq848jd301ctlz65qt1dw7j6	user_119	cmq848ij5002qlz65chlhp8ai	2026-06-10 13:39:57.063
cmq848jd401cvlz65wd9mtu6m	user_119	cmq848iht0018lz65i6s6humm	2026-06-10 13:39:57.064
cmq848jd401cxlz6573xu9lgt	user_031	cmq848ihc000ulz65um9y1gnx	2026-06-10 13:39:57.064
cmq848jd401czlz65cl4bxsyo	user_033	cmq848iky004ylz65gaaevnn2	2026-06-10 13:39:57.065
cmq848jd501d1lz65mqscfo1i	user_103	cmq848il00050lz65jly7d3ls	2026-06-10 13:39:57.065
cmq848jd501d3lz65r0olm8vu	user_076	cmq848ijr003glz651qntef1v	2026-06-10 13:39:57.066
cmq848jd601d5lz65f1ai69a1	user_086	cmq848ij3002olz65pe3rcpx3	2026-06-10 13:39:57.066
cmq848jd601d7lz65zfdqsyej	user_101	cmq848iki004elz65yy9n3pwk	2026-06-10 13:39:57.067
cmq848jd701d9lz658pgiuabl	user_084	cmq848iju003klz655h9g7ycn	2026-06-10 13:39:57.067
cmq848jd801dblz65nydkrua2	user_107	cmq848iic001ulz65hgqi8ctd	2026-06-10 13:39:57.068
cmq848jd901ddlz651930qhdy	user_046	cmq848il00050lz65jly7d3ls	2026-06-10 13:39:57.069
cmq848jda01dflz65nkb0zcb5	user_060	cmq848iln005olz65hnhu8jjb	2026-06-10 13:39:57.071
cmq848jdb01dhlz65k3aa48py	user_042	cmq848ij0002klz65fxbxd314	2026-06-10 13:39:57.072
cmq848jdc01djlz657mao4oro	user_107	cmq848ijf0034lz65wj1d3jhk	2026-06-10 13:39:57.072
cmq848jdc01dllz659bu3fduu	user_062	cmq848iiu002clz65afirolli	2026-06-10 13:39:57.073
cmq848jdd01dnlz65f2wwdk7i	user_034	cmq848ike004alz65zfska0qx	2026-06-10 13:39:57.073
cmq848jdd01dplz65e4z4zlnj	user_015	cmq848ilk005mlz65s3sdjsu8	2026-06-10 13:39:57.074
cmq848jde01drlz65hhuu9h2j	user_094	cmq848ii0001glz65zwwuce61	2026-06-10 13:39:57.075
cmq848jdf01dtlz65z5zhpowx	user_084	cmq848ik4003ylz65rlnlfu47	2026-06-10 13:39:57.075
\.


--
-- Data for Name: _prisma_migrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public._prisma_migrations (id, checksum, finished_at, migration_name, logs, rolled_back_at, started_at, applied_steps_count) FROM stdin;
067d3a5f-5bd4-4279-9072-4d72ae167586	cbec6eeb97e4c6dfcdcc0fb27107394d2cc36700b1d4cb6512e5fa32190a47d8	2026-06-10 10:36:51.65865-03	20260603230902_init		\N	2026-06-10 10:36:51.65865-03	0
7b7e94f1-8ecb-433a-a4e8-2fe1c8108735	0e5ddcc7bfe51dcdae925243a581ba13d6844779e763a9478b9428e8241dd772	2026-06-10 10:37:05.697176-03	20260607213112_stock_min_and_coupon_limits		\N	2026-06-10 10:37:05.697176-03	0
80e1592f-3760-4c98-a94a-e1799ae19c53	662c3e9fdab21ce320ba34142102de0355c209782ffd382d2314d447d3af5f1f	2026-06-10 10:37:16.702139-03	20260610120000_add_new_tables	\N	\N	2026-06-10 10:37:16.142784-03	1
\.


--
-- Name: AuditLog_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."AuditLog_id_seq"', 400, true);


--
-- Name: OrderItem_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."OrderItem_id_seq"', 496, true);


--
-- Name: ProductSize_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."ProductSize_id_seq"', 796, true);


--
-- Name: StockMovement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."StockMovement_id_seq"', 1517, true);


--
-- Name: Address Address_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Address"
    ADD CONSTRAINT "Address_pkey" PRIMARY KEY (id);


--
-- Name: AuditLog AuditLog_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."AuditLog"
    ADD CONSTRAINT "AuditLog_pkey" PRIMARY KEY (id);


--
-- Name: Brand Brand_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Brand"
    ADD CONSTRAINT "Brand_pkey" PRIMARY KEY (id);


--
-- Name: Category Category_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Category"
    ADD CONSTRAINT "Category_pkey" PRIMARY KEY (id);


--
-- Name: Coupon Coupon_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Coupon"
    ADD CONSTRAINT "Coupon_pkey" PRIMARY KEY (id);


--
-- Name: OrderItem OrderItem_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."OrderItem"
    ADD CONSTRAINT "OrderItem_pkey" PRIMARY KEY (id);


--
-- Name: Order Order_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Order"
    ADD CONSTRAINT "Order_pkey" PRIMARY KEY (id);


--
-- Name: Payment Payment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Payment"
    ADD CONSTRAINT "Payment_pkey" PRIMARY KEY (id);


--
-- Name: ProductSize ProductSize_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."ProductSize"
    ADD CONSTRAINT "ProductSize_pkey" PRIMARY KEY (id);


--
-- Name: Product Product_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Product"
    ADD CONSTRAINT "Product_pkey" PRIMARY KEY (id);


--
-- Name: Review Review_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Review"
    ADD CONSTRAINT "Review_pkey" PRIMARY KEY (id);


--
-- Name: StockMovement StockMovement_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."StockMovement"
    ADD CONSTRAINT "StockMovement_pkey" PRIMARY KEY (id);


--
-- Name: User User_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."User"
    ADD CONSTRAINT "User_pkey" PRIMARY KEY (id);


--
-- Name: Wishlist Wishlist_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Wishlist"
    ADD CONSTRAINT "Wishlist_pkey" PRIMARY KEY (id);


--
-- Name: _prisma_migrations _prisma_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public._prisma_migrations
    ADD CONSTRAINT _prisma_migrations_pkey PRIMARY KEY (id);


--
-- Name: Address_userId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Address_userId_idx" ON public."Address" USING btree ("userId");


--
-- Name: AuditLog_createdAt_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "AuditLog_createdAt_idx" ON public."AuditLog" USING btree ("createdAt");


--
-- Name: AuditLog_tableName_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "AuditLog_tableName_idx" ON public."AuditLog" USING btree ("tableName");


--
-- Name: Brand_name_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "Brand_name_key" ON public."Brand" USING btree (name);


--
-- Name: Category_name_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "Category_name_key" ON public."Category" USING btree (name);


--
-- Name: Category_slug_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "Category_slug_key" ON public."Category" USING btree (slug);


--
-- Name: Coupon_code_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "Coupon_code_key" ON public."Coupon" USING btree (code);


--
-- Name: OrderItem_orderId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "OrderItem_orderId_idx" ON public."OrderItem" USING btree ("orderId");


--
-- Name: OrderItem_productId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "OrderItem_productId_idx" ON public."OrderItem" USING btree ("productId");


--
-- Name: Order_createdAt_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Order_createdAt_idx" ON public."Order" USING btree ("createdAt");


--
-- Name: Order_status_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Order_status_idx" ON public."Order" USING btree (status);


--
-- Name: Order_userId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Order_userId_idx" ON public."Order" USING btree ("userId");


--
-- Name: Payment_orderId_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "Payment_orderId_key" ON public."Payment" USING btree ("orderId");


--
-- Name: ProductSize_productId_size_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "ProductSize_productId_size_key" ON public."ProductSize" USING btree ("productId", size);


--
-- Name: Product_active_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Product_active_idx" ON public."Product" USING btree (active);


--
-- Name: Product_brandId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Product_brandId_idx" ON public."Product" USING btree ("brandId");


--
-- Name: Product_categoryId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Product_categoryId_idx" ON public."Product" USING btree ("categoryId");


--
-- Name: Product_category_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Product_category_idx" ON public."Product" USING btree (category);


--
-- Name: Product_salesCount_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Product_salesCount_idx" ON public."Product" USING btree ("salesCount");


--
-- Name: Review_productId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Review_productId_idx" ON public."Review" USING btree ("productId");


--
-- Name: Review_userId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Review_userId_idx" ON public."Review" USING btree ("userId");


--
-- Name: StockMovement_createdAt_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "StockMovement_createdAt_idx" ON public."StockMovement" USING btree ("createdAt");


--
-- Name: StockMovement_productSizeId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "StockMovement_productSizeId_idx" ON public."StockMovement" USING btree ("productSizeId");


--
-- Name: User_email_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "User_email_key" ON public."User" USING btree (email);


--
-- Name: Wishlist_userId_productId_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "Wishlist_userId_productId_key" ON public."Wishlist" USING btree ("userId", "productId");


--
-- Name: Order trg_audit_status_pedido; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_status_pedido AFTER UPDATE OF status ON public."Order" FOR EACH ROW WHEN ((old.status IS DISTINCT FROM new.status)) EXECUTE FUNCTION public.fn_audit_status_pedido();


--
-- Name: ProductSize trg_movimento_estoque; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_movimento_estoque AFTER UPDATE OF stock ON public."ProductSize" FOR EACH ROW EXECUTE FUNCTION public.fn_registrar_movimento_estoque();


--
-- Name: Address Address_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Address"
    ADD CONSTRAINT "Address_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."User"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: AuditLog AuditLog_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."AuditLog"
    ADD CONSTRAINT "AuditLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."User"(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: OrderItem OrderItem_orderId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."OrderItem"
    ADD CONSTRAINT "OrderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES public."Order"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: OrderItem OrderItem_productId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."OrderItem"
    ADD CONSTRAINT "OrderItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES public."Product"(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: Order Order_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Order"
    ADD CONSTRAINT "Order_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."User"(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: Payment Payment_orderId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Payment"
    ADD CONSTRAINT "Payment_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES public."Order"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ProductSize ProductSize_productId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."ProductSize"
    ADD CONSTRAINT "ProductSize_productId_fkey" FOREIGN KEY ("productId") REFERENCES public."Product"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Product Product_brandId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Product"
    ADD CONSTRAINT "Product_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES public."Brand"(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: Product Product_categoryId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Product"
    ADD CONSTRAINT "Product_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES public."Category"(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: Review Review_productId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Review"
    ADD CONSTRAINT "Review_productId_fkey" FOREIGN KEY ("productId") REFERENCES public."Product"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Review Review_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Review"
    ADD CONSTRAINT "Review_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."User"(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: StockMovement StockMovement_productSizeId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."StockMovement"
    ADD CONSTRAINT "StockMovement_productSizeId_fkey" FOREIGN KEY ("productSizeId") REFERENCES public."ProductSize"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Wishlist Wishlist_productId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Wishlist"
    ADD CONSTRAINT "Wishlist_productId_fkey" FOREIGN KEY ("productId") REFERENCES public."Product"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Wishlist Wishlist_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Wishlist"
    ADD CONSTRAINT "Wishlist_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."User"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict otRxv2ahnFvlQVDgJjMaPpLVUx9N4QBn5dB3978cBxyhanERKYRgG1n632tYYqe

