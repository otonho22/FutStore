# Projetinho Fellas — Loja de Camisas de Futebol

MVP de e-commerce de camisas de futebol com autenticação, dashboard das mais vendidas, área de cliente, painel admin, cupons de desconto e pedidos rastreáveis. Tema escuro, sidebar intuitiva, mobile-first.

Stack: **React + Vite + TypeScript** (frontend), **Node.js + Express + TypeScript** (backend), **Firestore** (banco) e **Firebase Auth** (autenticação).

---

## Sumário

- [Funcionalidades do MVP](#funcionalidades-do-mvp)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Pré-requisitos](#pré-requisitos)
- [Setup do Firebase](#setup-do-firebase)
- [Variáveis de ambiente](#variáveis-de-ambiente)
- [Rodando localmente](#rodando-localmente)
- [Promovendo um usuário a admin](#promovendo-um-usuário-a-admin)
- [Regras de segurança do Firestore](#regras-de-segurança-do-firestore)
- [CI](#ci)
- [Mapa RF → implementação](#mapa-rf--implementação)
- [Fora do escopo / próximos passos](#fora-do-escopo--próximos-passos)

---

## Funcionalidades do MVP

- Cadastro e login (Firebase Auth — e-mail/senha)
- Dashboard com **Top 10 camisas mais vendidas** + gráfico de barras
- Catálogo navegável com filtro por categoria/time
- Detalhe do produto com seleção de tamanho (P/M/G/GG) e estoque por tamanho
- Carrinho (persistente no `localStorage`) com aplicação de cupom
- Checkout simulado (endereço + resumo → cria pedido em Firestore)
- Área "Meus Pedidos" com status e histórico
- Painel **Admin** (gated por role):
  - CRUD de produtos
  - CRUD de cupons (valor fixo ou percentual, validade, ativo/inativo)
  - Listagem e atualização de status de pedidos
- Sidebar fixa + dark theme + responsivo mobile-first

---

## Estrutura do repositório

```
.
├── README.md
├── .gitignore
├── .github/workflows/ci.yml      # lint + build em pull_request
├── backend/                       # Node.js + Express + firebase-admin
│   ├── src/
│   │   ├── index.ts
│   │   ├── firebase.ts
│   │   ├── middleware/
│   │   └── routes/
│   ├── scripts/setAdmin.ts        # promove um usuário a admin
│   └── package.json
└── frontend/                      # React + Vite + TS
    ├── src/
    │   ├── main.tsx
    │   ├── App.tsx
    │   ├── theme.css
    │   ├── lib/
    │   ├── context/
    │   ├── components/
    │   └── pages/
    └── package.json
```

---

## Pré-requisitos

- **Node.js 20+**
- **npm 10+**
- Conta no Firebase (plano Spark grátis basta para o MVP)

---

## Setup do Firebase

1. Acesse <https://console.firebase.google.com> → **Adicionar projeto** → dê um nome qualquer (`projetinho-fellas`).
2. No projeto criado, **Build → Authentication → Get started → Sign-in method → Email/Password → Enable**.
3. **Build → Firestore Database → Create database → Production mode → escolha uma região (ex. `southamerica-east1`)**.
4. **Project settings (⚙️) → General → Your apps → Web app (`</>`)** → registre um app (sem hosting). Copie o objeto `firebaseConfig` — ele vai no `.env` do frontend.
5. **Project settings → Service accounts → Generate new private key**. Salve o JSON como `backend/serviceAccountKey.json` (não comite — já está no `.gitignore`).
6. (Opcional) **Build → Firestore → Rules** → cole as [regras abaixo](#regras-de-segurança-do-firestore).

---

## Variáveis de ambiente

### `frontend/.env`

Copie `frontend/.env.example` para `frontend/.env` e preencha:

```env
VITE_FIREBASE_API_KEY=...
VITE_FIREBASE_AUTH_DOMAIN=...
VITE_FIREBASE_PROJECT_ID=...
VITE_FIREBASE_STORAGE_BUCKET=...
VITE_FIREBASE_MESSAGING_SENDER_ID=...
VITE_FIREBASE_APP_ID=...
VITE_API_URL=http://localhost:4000
```

### `backend/.env`

Copie `backend/.env.example` para `backend/.env`:

```env
PORT=4000
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
ALLOWED_ORIGIN=http://localhost:5173
SHIPPING_FIXED=25
```

---

## Rodando localmente

Em um terminal:

```bash
cd backend
npm install
npm run dev          # http://localhost:4000
```

Em outro terminal:

```bash
cd frontend
npm install
npm run dev          # http://localhost:5173
```

Abra <http://localhost:5173>, faça **Cadastro**, e você cai no dashboard. Para popular o catálogo, promova seu usuário a admin (próxima seção) e use o painel `/admin`.

---

## Promovendo um usuário a admin

1. Cadastre-se na aplicação com seu e-mail.
2. Rode o script:

```bash
cd backend
npm run set-admin -- seu-email@exemplo.com
```

3. Faça logout e login novamente para o token refletir a custom claim. O item **Admin** aparece na sidebar.

---

## Regras de segurança do Firestore

Cole em **Firestore → Rules**:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isSignedIn() { return request.auth != null; }
    function isAdmin() { return isSignedIn() && request.auth.token.role == 'admin'; }

    match /users/{uid} {
      allow read: if isSignedIn() && (request.auth.uid == uid || isAdmin());
      allow create: if isSignedIn() && request.auth.uid == uid;
      allow update, delete: if isAdmin();
    }

    match /products/{id} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /coupons/{id} {
      allow read: if isSignedIn();
      allow write: if isAdmin();
    }

    match /orders/{id} {
      allow read: if isSignedIn() && (resource.data.userId == request.auth.uid || isAdmin());
      allow create, update, delete: if isAdmin();
    }
  }
}
```

> Pedidos são sempre criados pelo backend (com privilégios admin do service account), por isso `create` cliente está bloqueado.

---

## CI

`.github/workflows/ci.yml` executa em **pull_request** dois jobs paralelos:

- `frontend-ci`: `npm ci` + `npm run lint` + `npm run build`
- `backend-ci`: `npm ci` + `npm run lint` + `npm run build`

Os PRs só devem ser mergeados se ambos os jobs passarem.

---

## Mapa RF → implementação

| RF | Funcionalidade | Onde |
|---|---|---|
| RF01–RF04 | CRUD de produtos | `backend/src/routes/products.ts`, `frontend/.../admin/AdminProducts.tsx` |
| RF05–RF08 | Variações (tamanho) com estoque + preço | campo `sizes` em `products` |
| RF10 | Exibição de variações | `ProductDetail.tsx` |
| RF16/RF17 | Upload simplificado (URL) | campo `imageUrl` + `images[]` |
| RF19/RF20 | Estoque por variação | decremento em `routes/orders.ts` |
| RF26/RF27/RF31/RF34/RF35 | Cupons fixo/percentual + validade + ativação + aplicação | `routes/coupons.ts`, `Cart.tsx`, `Checkout.tsx` |
| RF51–RF54 | Área do cliente / listagem / detalhes / status | `MyOrders.tsx`, `OrderDetail.tsx` |
| RF55/RF56 | Código de rastreio editável pelo admin | `AdminOrders.tsx` |
| RF70 | Registro de vendas (contador `salesCount`) | `routes/orders.ts` via `FieldValue.increment()` |
| RF77/RF79 | Ranking decrescente + gráfico | `Dashboard.tsx` |
| RNF01 | HTTPS | automático no deploy (Vercel/Render/Firebase Hosting) |
| RNF02 | LGPD | checkbox "Aceito os termos" no signup |
| RNF05 | Mobile-first | CSS media queries + sidebar drawer |
| RNF08 | Padrões de código | ESLint + TypeScript estrito |

## Fora do escopo / próximos passos

Não implementados neste MVP por restrição de tempo. Sugeridos como próximas iterações:

- RF11–RF15: tabela de medidas dinâmica
- RF18: zoom de imagem
- RF21–RF25: alertas e e-mails de estoque baixo
- RF36–RF41: integração Correios / cálculo real de frete (atualmente frete fixo via env `SHIPPING_FIXED`)
- RF42–RF50: detecção e e-mail de carrinho abandonado
- RF57: download de NF-e
- RF60–RF69: campanhas avançadas (leve X pague Y, desconto progressivo, melhor desconto)
- RF74–RF80 completos: BI avançado, exportação PDF/Excel/CSV, atualização automática
- RNF06: testes de stress (1.000 usuários simultâneos)
- RNF07: backup automatizado (configurar via gcloud scheduler + export)

---

## Publicar no GitHub

Para subir este repositório para o GitHub:

```bash
git init
git add .
git commit -m "feat: MVP inicial — auth, catálogo, carrinho, cupons, pedidos, admin"
gh repo create projetinho-fellas --public --source=. --push
# OU, sem gh CLI:
# crie o repo vazio em https://github.com/new
# git remote add origin https://github.com/<seu-user>/projetinho-fellas.git
# git branch -M main
# git push -u origin main
```

---

## Licença

Sem licença explícita — use livremente para fins de estudo.
