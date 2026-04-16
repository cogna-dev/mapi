import http from "k6/http";
import { check, sleep } from "k6";

const PORT = __ENV.PORT || "8081";
const BASE_URL = `http://localhost:${PORT}`;

export const options = {
  vus: 100,
  duration: "30s",
};

export default function () {
  // GET /pets
  {
    const res = http.get(`${BASE_URL}/pets`);
    check(res, { "GET /pets 200": (r) => r.status === 200 });
  }

  // POST /pets
  {
    const res = http.post(
      `${BASE_URL}/pets`,
      JSON.stringify({ name: `pet-${__VU}-${__ITER}` }),
      { headers: { "Content-Type": "application/json" } }
    );
    check(res, { "POST /pets 201": (r) => r.status === 201 });
  }

  // GET /pets/1
  {
    const res = http.get(`${BASE_URL}/pets/1`);
    check(res, { "GET /pets/1 200": (r) => r.status === 200 });
  }

  // GET /pets/999999 (expect 404)
  {
    const res = http.get(`${BASE_URL}/pets/999999`);
    check(res, { "GET /pets/999999 404": (r) => r.status === 404 });
  }

  sleep(0.1);
}
