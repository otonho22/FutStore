"""
Gera docs/Modelos.pdf com os 3 niveis de modelagem de dados:
  - Conceitual (MER em notacao Chen, diagrama PNG embutido)
  - Logico (esquema relacional textual + normalizacao)
  - Fisico (DDL SQL PostgreSQL completo)

Uso: py docs/build-modelos.py
Saida: docs/Modelos.pdf e docs/diagrama-chen.png
"""

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Ellipse, FancyBboxPatch, Polygon
from matplotlib.lines import Line2D

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm, mm
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Image,
    Table, TableStyle, KeepTogether, Preformatted,
)

DOCS = Path(__file__).resolve().parent
DIAGRAM_PATH = DOCS / "diagrama-chen.png"
PDF_PATH = DOCS / "Modelos.pdf"

# =============================================================================
# Diagrama Chen (matplotlib)
# =============================================================================

ENTITY_COLOR = "#1f3a8a"        # azul
ENTITY_FILL = "#e0e7ff"
WEAK_ENTITY_COLOR = "#5b21b6"   # roxo (entidade fraca)
WEAK_ENTITY_FILL = "#ede9fe"
REL_COLOR = "#92400e"           # marrom
REL_FILL = "#fef3c7"
ATTR_COLOR = "#065f46"          # verde
ATTR_FILL = "#d1fae5"
KEY_ATTR_COLOR = "#065f46"
LINE_COLOR = "#374151"
TEXT_COLOR = "#111827"


def draw_entity(ax, x, y, w, h, label, weak=False):
    color = WEAK_ENTITY_COLOR if weak else ENTITY_COLOR
    fill = WEAK_ENTITY_FILL if weak else ENTITY_FILL
    rect = Rectangle((x - w / 2, y - h / 2), w, h,
                     linewidth=1.8, edgecolor=color, facecolor=fill)
    ax.add_patch(rect)
    if weak:
        inner = Rectangle((x - w / 2 + 0.08, y - h / 2 + 0.08), w - 0.16, h - 0.16,
                          linewidth=1.2, edgecolor=color, facecolor="none")
        ax.add_patch(inner)
    ax.text(x, y, label, ha="center", va="center",
            fontsize=11, fontweight="bold", color=color)


def draw_relationship(ax, x, y, w, h, label, weak=False):
    poly = Polygon([[x, y + h / 2], [x + w / 2, y], [x, y - h / 2], [x - w / 2, y]],
                   linewidth=1.6, edgecolor=REL_COLOR, facecolor=REL_FILL)
    ax.add_patch(poly)
    if weak:
        inner = Polygon([[x, y + h / 2 - 0.08], [x + w / 2 - 0.10, y],
                         [x, y - h / 2 + 0.08], [x - w / 2 + 0.10, y]],
                        linewidth=1.2, edgecolor=REL_COLOR, facecolor="none")
        ax.add_patch(inner)
    ax.text(x, y, label, ha="center", va="center",
            fontsize=9, fontweight="bold", color=REL_COLOR)


def draw_attr(ax, x, y, label, w=0.95, h=0.42, key=False, multi=False, derived=False):
    el = Ellipse((x, y), w, h,
                 linewidth=1.3, edgecolor=ATTR_COLOR, facecolor=ATTR_FILL,
                 linestyle="--" if derived else "-")
    ax.add_patch(el)
    if multi:
        inner = Ellipse((x, y), w - 0.15, h - 0.10,
                        linewidth=1.0, edgecolor=ATTR_COLOR, facecolor="none")
        ax.add_patch(inner)
    fontstyle = {"fontsize": 7.5, "color": ATTR_COLOR,
                 "ha": "center", "va": "center"}
    if key:
        # sublinha o texto: usa text e adiciona uma linha abaixo do texto
        ax.text(x, y, label, **fontstyle, fontweight="bold")
        ax.plot([x - w / 2 + 0.10, x + w / 2 - 0.10], [y - 0.10, y - 0.10],
                color=ATTR_COLOR, linewidth=1.0)
    else:
        ax.text(x, y, label, **fontstyle)


def draw_line(ax, p1, p2, label=None, label_pos=0.5, dash=False):
    ax.plot([p1[0], p2[0]], [p1[1], p2[1]],
            color=LINE_COLOR, linewidth=1.2,
            linestyle="--" if dash else "-", zorder=1)
    if label:
        lx = p1[0] + (p2[0] - p1[0]) * label_pos
        ly = p1[1] + (p2[1] - p1[1]) * label_pos
        ax.text(lx, ly, label, fontsize=9, fontweight="bold",
                color="#7f1d1d",
                bbox=dict(boxstyle="round,pad=0.15", facecolor="white",
                          edgecolor="none", alpha=0.9))


def build_chen_diagram():
    fig, ax = plt.subplots(figsize=(16, 11))
    ax.set_xlim(0, 22)
    ax.set_ylim(0, 16)
    ax.set_aspect("equal")
    ax.axis("off")

    # --- ENTIDADES ---
    # User (esquerda)
    draw_entity(ax, 3, 13, 2.2, 1.0, "USER")
    # Order (centro)
    draw_entity(ax, 11, 13, 2.4, 1.0, "ORDER")
    # OrderItem (centro-baixo, fraca)
    draw_entity(ax, 11, 6, 2.6, 1.0, "ORDER_ITEM", weak=True)
    # Product (direita-baixo)
    draw_entity(ax, 18, 6, 2.4, 1.0, "PRODUCT")
    # ProductSize (extrema direita-baixo, fraca)
    draw_entity(ax, 18, 13, 2.8, 1.0, "PRODUCT_SIZE", weak=True)
    # Coupon (centro-alto)
    draw_entity(ax, 7, 9, 2.2, 1.0, "COUPON")

    # --- RELACIONAMENTOS ---
    draw_relationship(ax, 7, 13, 1.6, 0.9, "Realiza")
    draw_relationship(ax, 9, 10.5, 1.6, 0.9, "Aplica")
    draw_relationship(ax, 11, 9.5, 1.6, 0.9, "Contem", weak=True)
    draw_relationship(ax, 14.5, 6, 1.6, 0.9, "Referencia")
    draw_relationship(ax, 18, 9.5, 1.6, 0.9, "Possui_Tam", weak=True)

    # --- LINHAS RELACIONAIS COM CARDINALIDADES ---
    # User --1-- Realiza --N-- Order
    draw_line(ax, (4.1, 13), (6.2, 13), "1", 0.25)
    draw_line(ax, (7.8, 13), (9.8, 13), "N", 0.75)
    # Order --N-- Aplica --1-- Coupon  (na verdade Order pode ter 0..1)
    draw_line(ax, (11, 12.5), (9.5, 10.9))
    draw_line(ax, (8.5, 10.1), (7, 9.5), "0..1", 0.6)
    draw_line(ax, (8.5, 10.5), (10.3, 11.0), "N", 0.4)
    # Order --1-- Contem --N-- OrderItem (relacionamento identificante = duplo losango)
    draw_line(ax, (11, 12.5), (11, 9.95), "1", 0.25)
    draw_line(ax, (11, 9.05), (11, 6.5), "N", 0.7)
    # OrderItem --N-- Referencia --1-- Product
    draw_line(ax, (12.3, 6), (13.7, 6), "N", 0.3)
    draw_line(ax, (15.3, 6), (16.8, 6), "1", 0.7)
    # Product --1-- Possui_Tam --N-- ProductSize
    draw_line(ax, (18, 6.5), (18, 9.05), "1", 0.25)
    draw_line(ax, (18, 9.95), (18, 12.5), "N", 0.75)

    # --- ATRIBUTOS ---
    # User
    draw_attr(ax, 0.9, 14.6, "id", key=True)
    draw_attr(ax, 1.9, 15.2, "email")
    draw_attr(ax, 3.0, 15.2, "displayName")
    draw_attr(ax, 4.1, 15.2, "role")
    draw_attr(ax, 5.1, 14.6, "createdAt")
    for p in [(0.9, 14.6), (1.9, 15.2), (3.0, 15.2), (4.1, 15.2), (5.1, 14.6)]:
        ax.plot([p[0], 3], [p[1] - 0.20, 13.5], color=LINE_COLOR, linewidth=0.7)

    # Order
    draw_attr(ax, 9.5, 15.2, "id", key=True)
    draw_attr(ax, 10.6, 15.2, "subtotal")
    draw_attr(ax, 11.7, 15.2, "total")
    draw_attr(ax, 12.8, 15.2, "status")
    draw_attr(ax, 13.9, 14.6, "endereco", w=1.10)
    for p in [(9.5, 15.2), (10.6, 15.2), (11.7, 15.2), (12.8, 15.2), (13.9, 14.6)]:
        ax.plot([p[0], 11], [p[1] - 0.20, 13.5], color=LINE_COLOR, linewidth=0.7)

    # OrderItem
    draw_attr(ax, 8.4, 5.4, "id", key=True)
    draw_attr(ax, 9.5, 4.7, "quantity")
    draw_attr(ax, 10.6, 4.4, "unitPrice")
    draw_attr(ax, 11.7, 4.4, "size")
    draw_attr(ax, 12.8, 4.7, "name")
    for p in [(8.4, 5.4), (9.5, 4.7), (10.6, 4.4), (11.7, 4.4), (12.8, 4.7)]:
        ax.plot([p[0], 11], [p[1] + 0.20, 5.5], color=LINE_COLOR, linewidth=0.7)

    # Product (com multivalorado 'images')
    draw_attr(ax, 15.6, 5.4, "id", key=True)
    draw_attr(ax, 16.5, 4.4, "name")
    draw_attr(ax, 17.4, 4.0, "team")
    draw_attr(ax, 18.3, 4.0, "price")
    draw_attr(ax, 19.2, 4.4, "imageUrl")
    draw_attr(ax, 20.3, 4.7, "images", multi=True)
    draw_attr(ax, 21.0, 5.6, "salesCount")
    for p in [(15.6, 5.4), (16.5, 4.4), (17.4, 4.0), (18.3, 4.0),
              (19.2, 4.4), (20.3, 4.7), (21.0, 5.6)]:
        ax.plot([p[0], 18], [p[1] + 0.20, 5.5], color=LINE_COLOR, linewidth=0.7)

    # ProductSize
    draw_attr(ax, 15.6, 14.5, "id", key=True)
    draw_attr(ax, 16.7, 15.0, "size")
    draw_attr(ax, 18.0, 15.2, "stock")
    for p in [(15.6, 14.5), (16.7, 15.0), (18.0, 15.2)]:
        ax.plot([p[0], 18], [p[1] - 0.20, 13.5], color=LINE_COLOR, linewidth=0.7)

    # Coupon
    draw_attr(ax, 4.9, 9.4, "id", key=True)
    draw_attr(ax, 4.9, 8.4, "code")
    draw_attr(ax, 9.1, 8.4, "type")
    draw_attr(ax, 9.1, 9.4, "value")
    for p in [(4.9, 9.4), (4.9, 8.4)]:
        ax.plot([p[0] + 0.45, 7], [p[1], 9], color=LINE_COLOR, linewidth=0.7)
    for p in [(9.1, 8.4), (9.1, 9.4)]:
        ax.plot([p[0] - 0.45, 7], [p[1], 9], color=LINE_COLOR, linewidth=0.7)

    # Titulo e legenda
    ax.text(11, 15.7, "Modelo Conceitual (MER) — Notacao Chen",
            ha="center", fontsize=15, fontweight="bold", color=TEXT_COLOR)

    # Legenda
    legend_x, legend_y = 0.4, 1.4
    ax.add_patch(Rectangle((legend_x, legend_y), 0.6, 0.3,
                           edgecolor=ENTITY_COLOR, facecolor=ENTITY_FILL, linewidth=1.2))
    ax.text(legend_x + 0.8, legend_y + 0.15, "Entidade", fontsize=9, va="center")

    ax.add_patch(Rectangle((legend_x + 2.4, legend_y), 0.6, 0.3,
                           edgecolor=WEAK_ENTITY_COLOR, facecolor=WEAK_ENTITY_FILL, linewidth=1.2))
    ax.add_patch(Rectangle((legend_x + 2.48, legend_y + 0.06), 0.44, 0.18,
                           edgecolor=WEAK_ENTITY_COLOR, facecolor="none", linewidth=0.8))
    ax.text(legend_x + 3.2, legend_y + 0.15, "Entidade fraca", fontsize=9, va="center")

    poly = Polygon([[legend_x + 5.6, legend_y + 0.15],
                    [legend_x + 5.9, legend_y - 0.05],
                    [legend_x + 6.2, legend_y + 0.15],
                    [legend_x + 5.9, legend_y + 0.35]],
                   edgecolor=REL_COLOR, facecolor=REL_FILL, linewidth=1.2)
    ax.add_patch(poly)
    ax.text(legend_x + 6.6, legend_y + 0.15, "Relacionamento", fontsize=9, va="center")

    el = Ellipse((legend_x + 9.5, legend_y + 0.15), 0.6, 0.28,
                 edgecolor=ATTR_COLOR, facecolor=ATTR_FILL, linewidth=1.2)
    ax.add_patch(el)
    ax.text(legend_x + 10.1, legend_y + 0.15, "Atributo (sublinhado = chave)",
            fontsize=9, va="center")

    el = Ellipse((legend_x + 14.5, legend_y + 0.15), 0.6, 0.28,
                 edgecolor=ATTR_COLOR, facecolor=ATTR_FILL, linewidth=1.2)
    ax.add_patch(el)
    el_inner = Ellipse((legend_x + 14.5, legend_y + 0.15), 0.42, 0.18,
                       edgecolor=ATTR_COLOR, facecolor="none", linewidth=0.8)
    ax.add_patch(el_inner)
    ax.text(legend_x + 15.1, legend_y + 0.15, "Atributo multivalorado",
            fontsize=9, va="center")

    plt.tight_layout()
    plt.savefig(DIAGRAM_PATH, dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"[ok] diagrama: {DIAGRAM_PATH}")


# =============================================================================
# DDL SQL PostgreSQL
# =============================================================================

DDL_SQL = """\
-- =============================================================================
-- FutStore - DDL PostgreSQL (Modelo Fisico)
-- =============================================================================

-- Tabela de usuarios (id e o UID do Firebase Auth)
CREATE TABLE "User" (
    id              TEXT        PRIMARY KEY,
    email           TEXT        NOT NULL UNIQUE,
    "displayName"   TEXT,
    role            TEXT        NOT NULL DEFAULT 'customer',
    "acceptedTerms" BOOLEAN     NOT NULL DEFAULT FALSE,
    "createdAt"     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Catalogo de produtos
CREATE TABLE "Product" (
    id            TEXT             PRIMARY KEY,
    name          TEXT             NOT NULL,
    team          TEXT             NOT NULL,
    description   TEXT             NOT NULL DEFAULT '',
    price         DOUBLE PRECISION NOT NULL,
    "imageUrl"    TEXT             NOT NULL,
    images        TEXT[]           NOT NULL DEFAULT '{}',
    category      TEXT             NOT NULL,
    "salesCount"  INTEGER          NOT NULL DEFAULT 0,
    active        BOOLEAN          NOT NULL DEFAULT TRUE,
    "createdAt"   TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX "Product_category_idx"   ON "Product" (category);
CREATE INDEX "Product_active_idx"     ON "Product" (active);
CREATE INDEX "Product_salesCount_idx" ON "Product" ("salesCount");

-- Variacoes de tamanho/estoque (entidade fraca de Product)
CREATE TABLE "ProductSize" (
    id           SERIAL  PRIMARY KEY,
    "productId"  TEXT    NOT NULL,
    size         TEXT    NOT NULL,
    stock        INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "ProductSize_productId_size_key" UNIQUE ("productId", size),
    CONSTRAINT "ProductSize_productId_fkey" FOREIGN KEY ("productId")
        REFERENCES "Product"(id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Cupons de desconto
CREATE TABLE "Coupon" (
    id           TEXT             PRIMARY KEY,
    code         TEXT             NOT NULL UNIQUE,
    type         TEXT             NOT NULL,  -- 'fixed' | 'percent'
    value        DOUBLE PRECISION NOT NULL,
    "validUntil" TIMESTAMP        NOT NULL,
    active       BOOLEAN          NOT NULL DEFAULT TRUE,
    "createdAt"  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Pedidos (endereco e historico denormalizados intencionalmente)
CREATE TABLE "Order" (
    id                  TEXT             PRIMARY KEY,
    "userId"            TEXT             NOT NULL,
    "userEmail"         TEXT,
    "couponCode"        TEXT,
    subtotal            DOUBLE PRECISION NOT NULL,
    discount            DOUBLE PRECISION NOT NULL DEFAULT 0,
    shipping            DOUBLE PRECISION NOT NULL DEFAULT 0,
    total               DOUBLE PRECISION NOT NULL,
    status              TEXT             NOT NULL DEFAULT 'pendente',
    "trackingCode"      TEXT,

    -- Endereco (snapshot do pedido)
    "addressFullName"   TEXT NOT NULL,
    "addressStreet"     TEXT NOT NULL,
    "addressNumber"     TEXT NOT NULL,
    "addressComplement" TEXT,
    "addressCity"       TEXT NOT NULL,
    "addressState"      TEXT NOT NULL,
    "addressZip"        TEXT NOT NULL,

    "statusHistory"     JSONB     NOT NULL DEFAULT '[]'::jsonb,
    "createdAt"         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Order_userId_fkey" FOREIGN KEY ("userId")
        REFERENCES "User"(id) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "Order_userId_idx"    ON "Order" ("userId");
CREATE INDEX "Order_status_idx"    ON "Order" (status);
CREATE INDEX "Order_createdAt_idx" ON "Order" ("createdAt");

-- Itens de pedido (entidade fraca de Order)
CREATE TABLE "OrderItem" (
    id          SERIAL  PRIMARY KEY,
    "orderId"   TEXT    NOT NULL,
    "productId" TEXT    NOT NULL,
    name        TEXT    NOT NULL,          -- snapshot
    size        TEXT    NOT NULL,
    "unitPrice" DOUBLE PRECISION NOT NULL, -- snapshot do preco
    quantity    INTEGER NOT NULL,
    "imageUrl"  TEXT,

    CONSTRAINT "OrderItem_orderId_fkey" FOREIGN KEY ("orderId")
        REFERENCES "Order"(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "OrderItem_productId_fkey" FOREIGN KEY ("productId")
        REFERENCES "Product"(id) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "OrderItem_orderId_idx"   ON "OrderItem" ("orderId");
CREATE INDEX "OrderItem_productId_idx" ON "OrderItem" ("productId");
"""

# =============================================================================
# Conteudo textual (paragrafos)
# =============================================================================

INTRO_TEXT = """\
Este documento apresenta a modelagem de dados completa do sistema <b>FutStore</b>,
um e-commerce de camisas de futebol. A modelagem segue os tres niveis classicos
de projeto de banco de dados:
<br/><br/>
<b>1. Modelo Conceitual</b> - descreve o dominio do problema em alto nivel,
de forma independente de tecnologia, atraves do Modelo Entidade-Relacionamento (MER)
na notacao Chen.
<br/><br/>
<b>2. Modelo Logico</b> - traduz o conceitual para o paradigma relacional,
identificando tabelas, atributos, chaves primarias, chaves estrangeiras e restricoes.
<br/><br/>
<b>3. Modelo Fisico</b> - implementacao concreta no SGBD escolhido (PostgreSQL),
com tipos de dados nativos, indices e instrucoes DDL.
<br/><br/>
O sistema possui <b>6 entidades</b>: User, Product, ProductSize, Coupon, Order
e OrderItem. A autenticacao e delegada ao Firebase Auth - apenas o UID do usuario
e persistido na tabela User.
"""

ENTIDADES = [
    ("User", "Representa o cliente cadastrado na loja. O <i>id</i> e o UID gerado pelo "
             "Firebase Authentication, garantindo unicidade global. Pode assumir o papel "
             "<i>customer</i> (cliente comum) ou <i>admin</i> (administrador do sistema)."),
    ("Product", "Camisa de futebol disponivel para venda. Mantem catalogo de informacoes "
                "do produto (nome, time, descricao, preco, imagens) e o contador "
                "<i>salesCount</i> usado no ranking do dashboard."),
    ("ProductSize", "Variacao de tamanho de um Product (P, M, G, GG). Entidade fraca - "
                    "depende existencialmente de Product. Mantem o controle de estoque "
                    "por tamanho. Restricao UNIQUE(productId, size)."),
    ("Coupon", "Cupom de desconto. Pode ser de valor fixo (<i>fixed</i>) ou percentual "
               "(<i>percent</i>), com validade definida. O codigo (<i>code</i>) e unico "
               "e referenciado nos pedidos."),
    ("Order", "Pedido finalizado pelo cliente. Mantem snapshot do endereco e do historico "
              "de status (<i>statusHistory</i> em JSON). Total = subtotal - discount + shipping. "
              "Status: pendente, pago, enviado, entregue, cancelado."),
    ("OrderItem", "Item individual dentro de um pedido (entidade fraca de Order). Armazena "
                  "<i>snapshots</i> de nome e preco no momento da compra, garantindo "
                  "que alteracoes futuras no produto nao corrompam o historico."),
]

RELACIONAMENTOS = [
    ("Realiza", "User - Order", "1:N",
     "Um cliente realiza N pedidos; cada pedido pertence a exatamente um cliente."),
    ("Aplica_Cupom", "Order - Coupon", "N:0..1",
     "Um pedido pode aplicar zero ou um cupom; um cupom pode ser usado em N pedidos. "
     "Relacionamento implementado via coluna couponCode (string), sem FK forte para "
     "preservar o codigo mesmo apos exclusao do cupom."),
    ("Contem", "Order - OrderItem", "1:N (identificante)",
     "Pedido contem N itens. Relacionamento identificante: OrderItem nao existe sem "
     "Order pai. ON DELETE CASCADE."),
    ("Referencia", "OrderItem - Product", "N:1",
     "Cada item de pedido referencia um produto. Snapshot de nome/preco e mantido no item, "
     "permitindo evolucao do catalogo sem alterar pedidos passados. ON DELETE RESTRICT."),
    ("Possui_Tamanho", "Product - ProductSize", "1:N (identificante)",
     "Produto possui N variacoes de tamanho. Relacionamento identificante: tamanho nao "
     "existe sem o produto. ON DELETE CASCADE."),
]

LOGICO_SCHEMA = """\
USER (
  id           PK,   -- UID do Firebase Auth
  email        UNIQUE NOT NULL,
  displayName,
  role         NOT NULL DEFAULT 'customer',
  acceptedTerms NOT NULL DEFAULT FALSE,
  createdAt    NOT NULL
)

PRODUCT (
  id           PK,
  name, team, description, price, imageUrl, category  NOT NULL,
  images       (array textual, multivalorado),
  salesCount   NOT NULL DEFAULT 0,
  active       NOT NULL DEFAULT TRUE,
  createdAt    NOT NULL
)

PRODUCT_SIZE (
  id           PK,
  productId    FK -> PRODUCT.id  ON DELETE CASCADE,
  size, stock  NOT NULL,
  UNIQUE (productId, size)
)

COUPON (
  id           PK,
  code         UNIQUE NOT NULL,
  type         NOT NULL,   -- 'fixed' | 'percent'
  value        NOT NULL,
  validUntil   NOT NULL,
  active       NOT NULL DEFAULT TRUE,
  createdAt    NOT NULL
)

ORDER (
  id           PK,
  userId       FK -> USER.id  ON DELETE RESTRICT,
  userEmail,
  couponCode,                  -- referencia fraca a COUPON.code
  subtotal, discount, shipping, total  NOT NULL,
  status       NOT NULL DEFAULT 'pendente',
  trackingCode,
  addressFullName, addressStreet, addressNumber,
  addressComplement, addressCity, addressState, addressZip
                              -- endereco denormalizado (snapshot)
  statusHistory  (JSON),       -- historico de transicoes
  createdAt    NOT NULL
)

ORDER_ITEM (
  id           PK,
  orderId      FK -> ORDER.id    ON DELETE CASCADE,
  productId    FK -> PRODUCT.id  ON DELETE RESTRICT,
  name, size, unitPrice, quantity  NOT NULL,
  imageUrl
)
"""

NORMALIZACAO_TEXT = """\
<b>Forma normal alcancada:</b> o esquema esta em <b>3FN</b> (terceira forma normal).
Cada atributo nao-chave depende exclusivamente da chave primaria da sua tabela,
e nao ha dependencias transitivas.
<br/><br/>
<b>Denormalizacoes intencionais</b> (decisoes de projeto):
<br/><br/>
1. <b>Endereco dentro de Order</b> - os 7 campos de endereco (fullName, street, number,
complement, city, state, zip) sao denormalizados na tabela ORDER ao inves de criar uma
tabela ADDRESS separada. Justificativa: o endereco de entrega de um pedido especifico
deve ser imutavel (snapshot), mesmo que o cliente mude seu endereco cadastrado depois.
<br/><br/>
2. <b>Snapshot em OrderItem</b> - os campos <i>name</i>, <i>unitPrice</i> e <i>imageUrl</i>
sao duplicados em OrderItem. Justificativa: preserva o estado historico do pedido. Se o
preco ou nome do produto mudar, pedidos antigos continuam mostrando os valores reais
da compra.
<br/><br/>
3. <b>statusHistory como JSON</b> - ao inves de uma tabela ORDER_STATUS_HISTORY separada,
o historico de transicoes e armazenado em coluna <i>JSONB</i>. Justificativa: o historico
e sempre lido junto com o pedido e nunca consultado isoladamente. JSONB no PostgreSQL
mantem indexabilidade quando necessario.
<br/><br/>
4. <b>userEmail em Order</b> - duplica o email do User. Util para listagens administrativas
sem necessidade de JOIN, e tambem como snapshot caso o usuario mude o e-mail.
<br/><br/>
5. <b>couponCode (string) ao inves de FK</b> - Order referencia Coupon pelo codigo
textual. Permite manter o registro do cupom usado mesmo apos exclusao do cupom.
"""

# =============================================================================
# Geracao do PDF
# =============================================================================

def build_pdf():
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("CoverTitle", parent=styles["Title"],
                                 fontSize=26, leading=32, alignment=TA_CENTER,
                                 textColor=colors.HexColor("#1f3a8a"))
    subtitle_style = ParagraphStyle("CoverSub", parent=styles["Normal"],
                                    fontSize=14, leading=20, alignment=TA_CENTER,
                                    textColor=colors.HexColor("#374151"))
    h1 = ParagraphStyle("H1", parent=styles["Heading1"], fontSize=18, leading=24,
                        spaceAfter=10, textColor=colors.HexColor("#1f3a8a"))
    h2 = ParagraphStyle("H2", parent=styles["Heading2"], fontSize=14, leading=20,
                        spaceBefore=12, spaceAfter=8,
                        textColor=colors.HexColor("#5b21b6"))
    body = ParagraphStyle("Body", parent=styles["Normal"], fontSize=10.5,
                          leading=15, alignment=TA_JUSTIFY, spaceAfter=6)
    body_left = ParagraphStyle("BodyL", parent=body, alignment=TA_LEFT)
    code_style = ParagraphStyle("Code", parent=styles["Code"], fontSize=8.5,
                                leading=11, leftIndent=6, rightIndent=6,
                                textColor=colors.HexColor("#111827"),
                                backColor=colors.HexColor("#f3f4f6"),
                                borderColor=colors.HexColor("#e5e7eb"),
                                borderWidth=0.5, borderPadding=4,
                                fontName="Courier")

    doc = SimpleDocTemplate(str(PDF_PATH), pagesize=A4,
                            leftMargin=2.0 * cm, rightMargin=2.0 * cm,
                            topMargin=2.0 * cm, bottomMargin=2.0 * cm,
                            title="Modelagem de Dados - FutStore",
                            author="FutStore")

    story = []

    # ---------------- CAPA ----------------
    story.append(Spacer(1, 5 * cm))
    story.append(Paragraph("Modelagem de Dados", title_style))
    story.append(Spacer(1, 0.4 * cm))
    story.append(Paragraph("Conceitual &middot; Logico &middot; Fisico", subtitle_style))
    story.append(Spacer(1, 1.5 * cm))
    story.append(Paragraph("<b>Projeto:</b> FutStore - Loja de Camisas de Futebol",
                           subtitle_style))
    story.append(Paragraph("<b>SGBD:</b> PostgreSQL 14+", subtitle_style))
    story.append(Paragraph("<b>ORM:</b> Prisma 5.x", subtitle_style))
    story.append(Spacer(1, 5 * cm))
    story.append(Paragraph("<i>Documento gerado automaticamente a partir de "
                           "<font face='Courier'>backend/prisma/schema.prisma</font></i>",
                           ParagraphStyle("Foot", parent=styles["Italic"],
                                          alignment=TA_CENTER, fontSize=9,
                                          textColor=colors.grey)))
    story.append(PageBreak())

    # ---------------- SUMARIO ----------------
    story.append(Paragraph("Sumario", h1))
    sumario_data = [
        ["1.", "Introducao", ""],
        ["2.", "Identificacao das Entidades", ""],
        ["3.", "Modelo Conceitual (MER - Notacao Chen)", ""],
        ["4.", "Modelo Logico (Esquema Relacional)", ""],
        ["5.", "Modelo Fisico (DDL PostgreSQL)", ""],
        ["6.", "Dicionario de Dados", ""],
        ["", "Apendice A - Schema Prisma", ""],
    ]
    t = Table(sumario_data, colWidths=[1 * cm, 12 * cm, 3 * cm])
    t.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("LINEBELOW", (0, 0), (-1, -1), 0.3, colors.HexColor("#d1d5db")),
    ]))
    story.append(t)
    story.append(PageBreak())

    # ---------------- 1. INTRODUCAO ----------------
    story.append(Paragraph("1. Introducao", h1))
    story.append(Paragraph(INTRO_TEXT, body))
    story.append(Spacer(1, 0.4 * cm))

    # ---------------- 2. ENTIDADES ----------------
    story.append(Paragraph("2. Identificacao das Entidades", h1))
    for ent, desc in ENTIDADES:
        story.append(Paragraph(f"<b>{ent}</b>", h2))
        story.append(Paragraph(desc, body))
    story.append(PageBreak())

    # ---------------- 3. CONCEITUAL ----------------
    story.append(Paragraph("3. Modelo Conceitual (MER - Notacao Chen)", h1))
    story.append(Paragraph(
        "O diagrama abaixo representa as entidades, atributos e relacionamentos "
        "do dominio na notacao de Peter Chen. Entidades sao retangulos (duplos para "
        "entidades fracas), relacionamentos sao losangos (duplos para identificantes), "
        "atributos sao elipses ligadas a entidade dona (sublinhado indica chave; "
        "elipse dupla indica multivalorado). As cardinalidades sao anotadas nas linhas.",
        body))
    story.append(Spacer(1, 0.3 * cm))
    img = Image(str(DIAGRAM_PATH), width=17 * cm, height=11.6 * cm)
    story.append(img)
    story.append(Spacer(1, 0.4 * cm))

    story.append(Paragraph("Relacionamentos e cardinalidades", h2))
    rel_data = [["Relacionamento", "Entidades", "Cardinalidade", "Descricao"]]
    for nome, ents, card, desc in RELACIONAMENTOS:
        rel_data.append([nome, ents, card, Paragraph(desc, body_left)])
    rel_table = Table(rel_data, colWidths=[3 * cm, 3.5 * cm, 2.5 * cm, 7.5 * cm],
                      repeatRows=1)
    rel_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1f3a8a")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("ALIGN", (2, 0), (2, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#d1d5db")),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1),
         [colors.white, colors.HexColor("#f9fafb")]),
    ]))
    story.append(rel_table)
    story.append(PageBreak())

    # ---------------- 4. LOGICO ----------------
    story.append(Paragraph("4. Modelo Logico (Esquema Relacional)", h1))
    story.append(Paragraph(
        "Traducao do modelo conceitual para o paradigma relacional. Cada entidade "
        "vira uma tabela; relacionamentos 1:N viram chaves estrangeiras na entidade "
        "fraca; o atributo multivalorado <i>images</i> e representado como array "
        "textual nativo do PostgreSQL (em SGBDs sem suporte a arrays, seria uma "
        "tabela auxiliar PRODUCT_IMAGE).", body))
    story.append(Spacer(1, 0.3 * cm))
    story.append(Preformatted(LOGICO_SCHEMA, code_style))

    story.append(Spacer(1, 0.4 * cm))
    story.append(Paragraph("Normalizacao e denormalizacoes intencionais", h2))
    story.append(Paragraph(NORMALIZACAO_TEXT, body))
    story.append(PageBreak())

    # ---------------- 5. FISICO ----------------
    story.append(Paragraph("5. Modelo Fisico (DDL PostgreSQL)", h1))
    story.append(Paragraph(
        "Codigo DDL completo para criacao do schema no PostgreSQL 14+. Os identificadores "
        "estao entre aspas duplas para preservar camelCase (padrao gerado pelo Prisma). "
        "Tipos nativos do PostgreSQL: <font face='Courier'>TEXT</font> (string), "
        "<font face='Courier'>DOUBLE PRECISION</font> (float64), "
        "<font face='Courier'>INTEGER</font>, <font face='Courier'>BOOLEAN</font>, "
        "<font face='Courier'>TIMESTAMP</font>, <font face='Courier'>JSONB</font>, "
        "<font face='Courier'>TEXT[]</font> (array de string).", body))
    story.append(Spacer(1, 0.3 * cm))
    story.append(Preformatted(DDL_SQL, code_style))
    story.append(PageBreak())

    # ---------------- 6. DICIONARIO DE DADOS ----------------
    story.append(Paragraph("6. Dicionario de Dados", h1))
    story.append(Paragraph("Detalhamento de cada coluna por tabela, com tipo, restricoes "
                           "e descricao. PK = Primary Key, FK = Foreign Key, U = UNIQUE, "
                           "NN = NOT NULL.", body))

    dict_tables = [
        ("User", [
            ("id", "TEXT", "PK", "UID do Firebase Auth"),
            ("email", "TEXT", "U, NN", "E-mail unico"),
            ("displayName", "TEXT", "", "Nome de exibicao (opcional)"),
            ("role", "TEXT", "NN", "'customer' | 'admin'"),
            ("acceptedTerms", "BOOLEAN", "NN", "Aceite dos termos (LGPD)"),
            ("createdAt", "TIMESTAMP", "NN", "Data de cadastro"),
        ]),
        ("Product", [
            ("id", "TEXT", "PK", "Identificador cuid"),
            ("name", "TEXT", "NN", "Nome do produto"),
            ("team", "TEXT", "NN", "Time/selecao"),
            ("description", "TEXT", "NN", "Descricao (default '')"),
            ("price", "DOUBLE PRECISION", "NN", "Preco em reais"),
            ("imageUrl", "TEXT", "NN", "URL da imagem principal"),
            ("images", "TEXT[]", "NN", "Imagens adicionais (multivalorado)"),
            ("category", "TEXT", "NN", "Categoria (indexado)"),
            ("salesCount", "INTEGER", "NN", "Contador de vendas (indexado)"),
            ("active", "BOOLEAN", "NN", "Ativo para venda (indexado)"),
            ("createdAt", "TIMESTAMP", "NN", "Data de cadastro"),
        ]),
        ("ProductSize", [
            ("id", "SERIAL", "PK", "Auto-incremento"),
            ("productId", "TEXT", "FK->Product, NN", "Produto pai (cascade delete)"),
            ("size", "TEXT", "NN", "P | M | G | GG"),
            ("stock", "INTEGER", "NN", "Estoque desta variacao"),
            ("UNIQUE", "(productId, size)", "U", "Sem duplicacao de tamanho por produto"),
        ]),
        ("Coupon", [
            ("id", "TEXT", "PK", "Identificador cuid"),
            ("code", "TEXT", "U, NN", "Codigo do cupom (uppercase)"),
            ("type", "TEXT", "NN", "'fixed' | 'percent'"),
            ("value", "DOUBLE PRECISION", "NN", "Valor (R$ ou %)"),
            ("validUntil", "TIMESTAMP", "NN", "Data de validade"),
            ("active", "BOOLEAN", "NN", "Cupom habilitado"),
            ("createdAt", "TIMESTAMP", "NN", "Data de criacao"),
        ]),
        ("Order", [
            ("id", "TEXT", "PK", "Identificador cuid"),
            ("userId", "TEXT", "FK->User, NN", "Cliente"),
            ("userEmail", "TEXT", "", "Snapshot do email"),
            ("couponCode", "TEXT", "", "Cupom aplicado (string solta)"),
            ("subtotal", "DOUBLE PRECISION", "NN", "Soma dos itens"),
            ("discount", "DOUBLE PRECISION", "NN", "Desconto aplicado"),
            ("shipping", "DOUBLE PRECISION", "NN", "Frete"),
            ("total", "DOUBLE PRECISION", "NN", "Total final"),
            ("status", "TEXT", "NN", "pendente|pago|enviado|entregue|cancelado"),
            ("trackingCode", "TEXT", "", "Codigo de rastreio"),
            ("addressFullName..addressZip", "TEXT", "NN (maioria)", "Endereco snapshot (7 colunas)"),
            ("statusHistory", "JSONB", "NN", "Array de transicoes"),
            ("createdAt", "TIMESTAMP", "NN", "Data do pedido"),
        ]),
        ("OrderItem", [
            ("id", "SERIAL", "PK", "Auto-incremento"),
            ("orderId", "TEXT", "FK->Order, NN", "Pedido pai (cascade)"),
            ("productId", "TEXT", "FK->Product, NN", "Produto referenciado"),
            ("name", "TEXT", "NN", "Snapshot do nome"),
            ("size", "TEXT", "NN", "Tamanho comprado"),
            ("unitPrice", "DOUBLE PRECISION", "NN", "Snapshot do preco unitario"),
            ("quantity", "INTEGER", "NN", "Quantidade"),
            ("imageUrl", "TEXT", "", "Snapshot da imagem"),
        ]),
    ]

    for tname, cols in dict_tables:
        story.append(Paragraph(f"{tname}", h2))
        rows = [["Coluna", "Tipo", "Restricoes", "Descricao"]]
        for c, tp, restr, desc in cols:
            rows.append([c, tp, restr, desc])
        tbl = Table(rows, colWidths=[5 * cm, 3.5 * cm, 3 * cm, 5 * cm],
                    repeatRows=1)
        tbl.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#5b21b6")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTNAME", (0, 1), (0, -1), "Courier"),
            ("FONTNAME", (1, 1), (1, -1), "Courier"),
            ("FONTSIZE", (0, 0), (-1, -1), 8.5),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#e5e7eb")),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1),
             [colors.white, colors.HexColor("#faf5ff")]),
        ]))
        story.append(KeepTogether(tbl))
        story.append(Spacer(1, 0.3 * cm))

    story.append(PageBreak())

    # ---------------- APENDICE: SCHEMA PRISMA ----------------
    story.append(Paragraph("Apendice A - Schema Prisma original", h1))
    story.append(Paragraph(
        "Arquivo fonte: <font face='Courier'>backend/prisma/schema.prisma</font>", body))
    schema_path = DOCS.parent / "backend" / "prisma" / "schema.prisma"
    if schema_path.exists():
        schema_text = schema_path.read_text(encoding="utf-8")
        story.append(Preformatted(schema_text, code_style))
    else:
        story.append(Paragraph("(arquivo nao encontrado)", body))

    # ---------------- BUILD ----------------
    doc.build(story)
    print(f"[ok] pdf: {PDF_PATH}")


if __name__ == "__main__":
    DOCS.mkdir(exist_ok=True)
    build_chen_diagram()
    build_pdf()
