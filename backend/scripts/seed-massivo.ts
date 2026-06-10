import 'dotenv/config';
import { prisma } from '../src/db.js';
import { faker } from '@faker-js/faker/locale/pt_BR';

faker.seed(42);

const CATEGORIES = [
  { name: 'Times Brasileiros', slug: 'times-brasileiros' },
  { name: 'Times Europeus', slug: 'times-europeus' },
  { name: 'Seleções', slug: 'selecoes' },
  { name: 'Retrô', slug: 'retro' },
  { name: 'Edição Limitada', slug: 'edicao-limitada' },
  { name: 'Infantil', slug: 'infantil' },
];

const BRANDS = [
  { name: 'Nike', logoUrl: '/brands/nike.png' },
  { name: 'Adidas', logoUrl: '/brands/adidas.png' },
  { name: 'Puma', logoUrl: '/brands/puma.png' },
  { name: 'Umbro', logoUrl: '/brands/umbro.png' },
  { name: 'New Balance', logoUrl: '/brands/new-balance.png' },
];

const TEAMS_EXTENDED = [
  { team: 'Flamengo', cat: 'Times Brasileiros', brand: 'Adidas', price: 349.9 },
  { team: 'Palmeiras', cat: 'Times Brasileiros', brand: 'Puma', price: 329.9 },
  { team: 'Corinthians', cat: 'Times Brasileiros', brand: 'Nike', price: 319.9 },
  { team: 'São Paulo', cat: 'Times Brasileiros', brand: 'Adidas', price: 319.9 },
  { team: 'Grêmio', cat: 'Times Brasileiros', brand: 'Umbro', price: 309.9 },
  { team: 'Internacional', cat: 'Times Brasileiros', brand: 'Adidas', price: 309.9 },
  { team: 'Vasco', cat: 'Times Brasileiros', brand: 'Umbro', price: 299.9 },
  { team: 'Botafogo', cat: 'Times Brasileiros', brand: 'Puma', price: 299.9 },
  { team: 'Fluminense', cat: 'Times Brasileiros', brand: 'Umbro', price: 299.9 },
  { team: 'Atlético-MG', cat: 'Times Brasileiros', brand: 'Adidas', price: 309.9 },
  { team: 'Cruzeiro', cat: 'Times Brasileiros', brand: 'Adidas', price: 299.9 },
  { team: 'Santos', cat: 'Times Brasileiros', brand: 'Umbro', price: 299.9 },
  { team: 'Bahia', cat: 'Times Brasileiros', brand: 'Puma', price: 289.9 },
  { team: 'Fortaleza', cat: 'Times Brasileiros', brand: 'Nike', price: 289.9 },
  { team: 'Real Madrid', cat: 'Times Europeus', brand: 'Adidas', price: 499.9 },
  { team: 'FC Barcelona', cat: 'Times Europeus', brand: 'Nike', price: 499.9 },
  { team: 'Manchester City', cat: 'Times Europeus', brand: 'Puma', price: 459.9 },
  { team: 'Liverpool', cat: 'Times Europeus', brand: 'Nike', price: 459.9 },
  { team: 'Bayern de Munique', cat: 'Times Europeus', brand: 'Adidas', price: 479.9 },
  { team: 'PSG', cat: 'Times Europeus', brand: 'Nike', price: 479.9 },
  { team: 'Juventus', cat: 'Times Europeus', brand: 'Adidas', price: 459.9 },
  { team: 'Milan', cat: 'Times Europeus', brand: 'Puma', price: 449.9 },
  { team: 'Inter de Milão', cat: 'Times Europeus', brand: 'Nike', price: 449.9 },
  { team: 'Seleção Brasileira', cat: 'Seleções', brand: 'Nike', price: 389.9 },
  { team: 'Seleção Argentina', cat: 'Seleções', brand: 'Adidas', price: 389.9 },
  { team: 'Seleção Alemanha', cat: 'Seleções', brand: 'Adidas', price: 379.9 },
  { team: 'Seleção França', cat: 'Seleções', brand: 'Nike', price: 379.9 },
  { team: 'Seleção Portugal', cat: 'Seleções', brand: 'Nike', price: 379.9 },
  { team: 'Seleção Espanha', cat: 'Seleções', brand: 'Adidas', price: 369.9 },
  { team: 'Seleção Itália', cat: 'Seleções', brand: 'Adidas', price: 369.9 },
  { team: 'Seleção Inglaterra', cat: 'Seleções', brand: 'Nike', price: 369.9 },
  { team: 'Seleção Japão', cat: 'Seleções', brand: 'Adidas', price: 349.9 },
  { team: 'Seleção México', cat: 'Seleções', brand: 'Adidas', price: 349.9 },
  { team: 'Flamengo Retrô 81', cat: 'Retrô', brand: 'Umbro', price: 259.9 },
  { team: 'Brasil Retrô 70', cat: 'Retrô', brand: 'Nike', price: 279.9 },
  { team: 'Santos Retrô Pelé', cat: 'Retrô', brand: 'Umbro', price: 269.9 },
  { team: 'Borussia Dortmund', cat: 'Times Europeus', brand: 'Puma', price: 449.9 },
  { team: 'Chelsea', cat: 'Times Europeus', brand: 'Nike', price: 459.9 },
  { team: 'Arsenal', cat: 'Times Europeus', brand: 'Adidas', price: 459.9 },
  { team: 'Atlético de Madrid', cat: 'Times Europeus', brand: 'Nike', price: 449.9 },
];

const VARIANTS = ['Camisa I (Home)', 'Camisa II (Away)', 'Camisa III (Third)'];
const SIZES = ['P', 'M', 'G', 'GG'];
const STATES = ['SP', 'RJ', 'MG', 'RS', 'PR', 'BA', 'PE', 'CE', 'DF', 'GO', 'SC', 'PA', 'AM', 'MA', 'ES'];
const ORDER_STATUSES = ['pendente', 'pago', 'enviado', 'entregue', 'cancelado'];
const PAYMENT_METHODS = ['credit_card', 'pix', 'boleto'];
const CARD_BRANDS = ['Visa', 'Mastercard', 'Elo', 'Amex'];

const REVIEW_COMMENTS = [
  'Ótima qualidade, tecido leve e confortável.',
  'Chegou rápido, produto excelente!',
  'Muito bonita, igual à original.',
  'O tamanho ficou perfeito.',
  'Material de boa qualidade, recomendo.',
  'Achei o tecido um pouco fino.',
  'Camisa bonita mas demorou pra chegar.',
  'Presente pro meu filho, ele adorou!',
  'Nota 10, já é minha terceira compra.',
  'Cor vibrante, estampa perfeita.',
  'Bom custo-benefício.',
  'Esperava melhor qualidade pelo preço.',
  'Excelente acabamento, vale cada centavo.',
  'Comprei pro meu marido e ele amou.',
  'Tecido respirável, ótimo pra jogar.',
  'A costura poderia ser melhor.',
  'Produto exatamente como na foto.',
  'Entrega antes do prazo, adorei!',
  'Muito confortável pra usar no dia a dia.',
  'Camisa linda, já quero a do próximo ano.',
];

async function main() {
  console.log('🌱 Seed massivo — populando todas as 14 tabelas...\n');

  // Clean everything in dependency order
  console.log('Limpando dados existentes...');
  await prisma.auditLog.deleteMany();
  await prisma.stockMovement.deleteMany();
  await prisma.payment.deleteMany();
  await prisma.review.deleteMany();
  await prisma.wishlist.deleteMany();
  await prisma.address.deleteMany();
  await prisma.orderItem.deleteMany();
  await prisma.order.deleteMany();
  await prisma.productSize.deleteMany();
  await prisma.product.deleteMany();
  await prisma.coupon.deleteMany();
  await prisma.category.deleteMany();
  await prisma.brand.deleteMany();
  await prisma.user.deleteMany();

  // 1. Categories
  console.log('1/10 Categories...');
  const categoryMap: Record<string, string> = {};
  for (const c of CATEGORIES) {
    const cat = await prisma.category.create({ data: c });
    categoryMap[c.name] = cat.id;
  }

  // 2. Brands
  console.log('2/10 Brands...');
  const brandMap: Record<string, string> = {};
  for (const b of BRANDS) {
    const brand = await prisma.brand.create({ data: b });
    brandMap[b.name] = brand.id;
  }

  // 3. Products (~100 = 33 teams x 3 variants)
  console.log('3/10 Products...');
  const productIds: string[] = [];
  const productSizeIds: number[] = [];
  const productPrices: Record<string, number> = {};
  const productNames: Record<string, string> = {};

  for (const t of TEAMS_EXTENDED) {
    const numVariants = faker.helpers.arrayElement([2, 3, 3]);
    for (let vi = 0; vi < numVariants; vi++) {
      const price = t.price + (vi === 2 ? 20 : 0);
      const name = `${t.team} ${VARIANTS[vi]} 24/25`;
      const product = await prisma.product.create({
        data: {
          name,
          team: t.team,
          description: `Camisa oficial ${t.team} temporada 24/25. Tecido Dri-Fit com tecnologia de ventilação.`,
          price,
          imageUrl: `/jerseys/${t.team.toLowerCase().replace(/ /g, '-').replace(/[éê]/g, 'e').replace(/ã/g, 'a').replace(/ç/g, 'c')}.jpg`,
          category: t.cat,
          categoryId: categoryMap[t.cat] ?? null,
          brandId: brandMap[t.brand] ?? null,
          salesCount: faker.number.int({ min: 2, max: 50 }),
          active: true,
          sizes: {
            create: SIZES.map(s => ({
              size: s,
              stock: faker.number.int({ min: 3, max: 25 }),
            })),
          },
        },
        include: { sizes: true },
      });
      productIds.push(product.id);
      productPrices[product.id] = price;
      productNames[product.id] = name;
      for (const sz of product.sizes) {
        productSizeIds.push(sz.id);
      }
    }
  }
  console.log(`   ${productIds.length} produtos criados.`);

  // 4. Users (120)
  console.log('4/10 Users...');
  const userIds: string[] = [];
  for (let i = 0; i < 120; i++) {
    const firstName = faker.person.firstName();
    const lastName = faker.person.lastName();
    const uid = `user_${String(i + 1).padStart(3, '0')}`;
    const user = await prisma.user.create({
      data: {
        id: uid,
        email: `${firstName.toLowerCase()}.${lastName.toLowerCase()}${i}@email.com`,
        displayName: `${firstName} ${lastName}`,
        role: i < 2 ? 'admin' : 'customer',
        acceptedTerms: true,
      },
    });
    userIds.push(user.id);
  }
  console.log(`   ${userIds.length} usuários criados.`);

  // 5. Addresses (~150)
  console.log('5/10 Addresses...');
  let addressCount = 0;
  for (const uid of userIds) {
    const numAddr = faker.helpers.arrayElement([1, 1, 2, 2, 3]);
    for (let a = 0; a < numAddr; a++) {
      await prisma.address.create({
        data: {
          userId: uid,
          fullName: faker.person.fullName(),
          street: faker.location.street(),
          number: String(faker.number.int({ min: 1, max: 9999 })),
          complement: faker.helpers.maybe(() => `Apto ${faker.number.int({ min: 1, max: 500 })}`, { probability: 0.4 }) ?? null,
          city: faker.location.city(),
          state: faker.helpers.arrayElement(STATES),
          zip: faker.string.numeric(8),
          isDefault: a === 0,
        },
      });
      addressCount++;
    }
  }
  console.log(`   ${addressCount} endereços criados.`);

  // 6. Coupons (5)
  console.log('6/10 Coupons...');
  const couponCodes = ['BEMVINDO10', 'FUTSTORE20', 'FRETE15', 'BLACK30', 'COPA2026'];
  const coupons = [];
  for (let i = 0; i < couponCodes.length; i++) {
    const c = await prisma.coupon.create({
      data: {
        code: couponCodes[i],
        type: i < 3 ? 'percent' : 'fixed',
        value: [10, 20, 15, 30, 50][i],
        validUntil: new Date(Date.now() + 1000 * 60 * 60 * 24 * 90),
        active: true,
      },
    });
    coupons.push(c);
  }

  // 7. Orders (120) + OrderItems (~350)
  console.log('7/10 Orders + OrderItems...');
  const orderIds: string[] = [];
  let totalItems = 0;
  for (let i = 0; i < 120; i++) {
    const userId = faker.helpers.arrayElement(userIds);
    const numItems = faker.helpers.arrayElement([1, 1, 2, 2, 3, 4]);
    const status = faker.helpers.weightedArrayElement([
      { value: 'entregue', weight: 50 },
      { value: 'pago', weight: 20 },
      { value: 'enviado', weight: 15 },
      { value: 'pendente', weight: 10 },
      { value: 'cancelado', weight: 5 },
    ]);
    const useCoupon = faker.datatype.boolean(0.3);
    const couponCode = useCoupon ? faker.helpers.arrayElement(couponCodes) : null;

    const selectedProducts = faker.helpers.arrayElements(productIds, numItems);
    let subtotal = 0;
    const items = selectedProducts.map(pid => {
      const qty = faker.helpers.arrayElement([1, 1, 1, 2]);
      const price = productPrices[pid];
      subtotal += price * qty;
      return {
        productId: pid,
        name: productNames[pid],
        size: faker.helpers.arrayElement(SIZES),
        unitPrice: price,
        quantity: qty,
        imageUrl: `/jerseys/placeholder.jpg`,
      };
    });

    const discount = couponCode ? subtotal * 0.1 : 0;
    const shipping = 25;
    const total = subtotal - discount + shipping;
    const createdAt = faker.date.between({
      from: new Date('2025-12-01'),
      to: new Date('2026-06-09'),
    });

    const state = faker.helpers.arrayElement(STATES);
    const order = await prisma.order.create({
      data: {
        userId,
        userEmail: `${userId}@email.com`,
        couponCode,
        subtotal,
        discount,
        shipping,
        total,
        status,
        trackingCode: ['enviado', 'entregue'].includes(status) ? `BR${faker.string.numeric(13)}` : null,
        paymentMethod: faker.helpers.arrayElement(PAYMENT_METHODS),
        paymentBrand: faker.helpers.arrayElement(CARD_BRANDS),
        paymentLast4: faker.string.numeric(4),
        paymentHolderName: faker.person.fullName(),
        addressFullName: faker.person.fullName(),
        addressStreet: faker.location.street(),
        addressNumber: String(faker.number.int({ min: 1, max: 9999 })),
        addressComplement: faker.helpers.maybe(() => `Apto ${faker.number.int({ min: 1, max: 200 })}`) ?? null,
        addressCity: faker.location.city(),
        addressState: state,
        addressZip: faker.string.numeric(8),
        statusHistory: JSON.stringify([{ status, at: createdAt.toISOString() }]),
        createdAt,
        items: { create: items },
      },
    });
    orderIds.push(order.id);
    totalItems += items.length;
  }
  console.log(`   ${orderIds.length} pedidos, ${totalItems} itens criados.`);

  // 8. Payments (1 per order)
  console.log('8/10 Payments...');
  const orders = await prisma.order.findMany({ select: { id: true, total: true, paymentMethod: true, paymentBrand: true, paymentLast4: true, paymentHolderName: true, status: true, createdAt: true } });
  for (const o of orders) {
    await prisma.payment.create({
      data: {
        orderId: o.id,
        method: o.paymentMethod,
        brand: o.paymentBrand,
        last4: o.paymentLast4,
        holderName: o.paymentHolderName,
        amount: o.total,
        status: o.status === 'cancelado' ? 'rejected' : 'approved',
        paidAt: o.createdAt,
      },
    });
  }
  console.log(`   ${orders.length} pagamentos criados.`);

  // 9. Reviews (150)
  console.log('9/10 Reviews...');
  let reviewCount = 0;
  const usedPairs = new Set<string>();
  for (let i = 0; i < 150; i++) {
    const userId = faker.helpers.arrayElement(userIds);
    const productId = faker.helpers.arrayElement(productIds);
    const key = `${userId}:${productId}`;
    if (usedPairs.has(key)) continue;
    usedPairs.add(key);
    await prisma.review.create({
      data: {
        productId,
        userId,
        rating: faker.helpers.weightedArrayElement([
          { value: 5, weight: 40 },
          { value: 4, weight: 30 },
          { value: 3, weight: 15 },
          { value: 2, weight: 10 },
          { value: 1, weight: 5 },
        ]),
        comment: faker.helpers.arrayElement(REVIEW_COMMENTS),
        createdAt: faker.date.between({ from: new Date('2025-12-01'), to: new Date('2026-06-09') }),
      },
    });
    reviewCount++;
  }
  console.log(`   ${reviewCount} reviews criadas.`);

  // 10. Wishlists (~150, unique user+product)
  console.log('10/10 Wishlists + StockMovements + AuditLogs...');
  let wishCount = 0;
  const wishPairs = new Set<string>();
  for (let i = 0; i < 180; i++) {
    const userId = faker.helpers.arrayElement(userIds);
    const productId = faker.helpers.arrayElement(productIds);
    const key = `${userId}:${productId}`;
    if (wishPairs.has(key)) continue;
    wishPairs.add(key);
    await prisma.wishlist.create({
      data: { userId, productId },
    });
    wishCount++;
  }
  console.log(`   ${wishCount} wishlists criadas.`);

  // StockMovements (~400)
  let smCount = 0;
  for (const psId of productSizeIds) {
    const numMoves = faker.helpers.arrayElement([1, 1, 2, 2, 3]);
    for (let m = 0; m < numMoves; m++) {
      await prisma.stockMovement.create({
        data: {
          productSizeId: psId,
          type: faker.helpers.weightedArrayElement([
            { value: 'in', weight: 60 },
            { value: 'out', weight: 40 },
          ]),
          quantity: faker.number.int({ min: 1, max: 20 }),
          reason: faker.helpers.arrayElement(['Compra fornecedor', 'Venda', 'Ajuste inventário', 'Devolução', 'Reposição']),
          createdAt: faker.date.between({ from: new Date('2025-12-01'), to: new Date('2026-06-09') }),
        },
      });
      smCount++;
    }
  }
  console.log(`   ${smCount} movimentações de estoque criadas.`);

  // AuditLogs (~200)
  let alCount = 0;
  for (let i = 0; i < 200; i++) {
    await prisma.auditLog.create({
      data: {
        userId: faker.helpers.maybe(() => faker.helpers.arrayElement(userIds), { probability: 0.8 }) ?? null,
        tableName: faker.helpers.arrayElement(['Product', 'Order', 'User', 'ProductSize', 'Coupon', 'Review']),
        action: faker.helpers.arrayElement(['INSERT', 'UPDATE', 'DELETE']),
        payload: { detail: faker.lorem.sentence() },
        createdAt: faker.date.between({ from: new Date('2025-12-01'), to: new Date('2026-06-09') }),
      },
    });
    alCount++;
  }
  console.log(`   ${alCount} logs de auditoria criados.`);

  // Final count
  console.log('\n✅ Seed completo! Contagem final:');
  const counts = await Promise.all([
    prisma.category.count(),
    prisma.brand.count(),
    prisma.product.count(),
    prisma.productSize.count(),
    prisma.user.count(),
    prisma.address.count(),
    prisma.coupon.count(),
    prisma.order.count(),
    prisma.orderItem.count(),
    prisma.payment.count(),
    prisma.review.count(),
    prisma.wishlist.count(),
    prisma.stockMovement.count(),
    prisma.auditLog.count(),
  ]);
  const labels = ['Category', 'Brand', 'Product', 'ProductSize', 'User', 'Address', 'Coupon', 'Order', 'OrderItem', 'Payment', 'Review', 'Wishlist', 'StockMovement', 'AuditLog'];
  labels.forEach((l, i) => console.log(`   ${l}: ${counts[i]}`));
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
