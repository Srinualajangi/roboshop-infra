import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE || 'http://web.roboshop-qa.svc.cluster.local:8080';

export const options = {
  stages: [                     // stepped load: hold each level 2 minutes
    { duration: '30s', target: 10 },  { duration: '2m', target: 10 },
    { duration: '30s', target: 25 },  { duration: '2m', target: 25 },
    { duration: '30s', target: 50 },  { duration: '2m', target: 50 },
    { duration: '30s', target: 100 }, { duration: '2m', target: 100 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {                 // our SLO expressed as a test pass/fail
    http_req_failed:   ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

export default function () {
  const products = http.get(`${BASE}/api/catalogue/products`, { tags: { name: 'products' } });
  check(products, { 'products 200': (r) => r.status === 200 });
  let sku = 'Watson';
  try { sku = products.json()[Math.floor(Math.random() * products.json().length)].sku; } catch (e) {}
  http.get(`${BASE}/api/catalogue/product/${sku}`, { tags: { name: 'product' } });
  http.get(`${BASE}/api/ratings/api/fetch/${sku}`, { tags: { name: 'ratings' } });
  const id = http.get(`${BASE}/api/user/uniqueid`).json('uuid') || 'anon';
  http.get(`${BASE}/api/cart/add/${id}/${sku}/1`, { tags: { name: 'cart-add' } });
  sleep(1);
}
