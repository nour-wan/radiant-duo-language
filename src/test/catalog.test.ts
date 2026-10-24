import { describe, expect, it } from "vitest";
import { getProducts } from "@/services/catalog";

describe("Alas catalog additions", () => {
  it.each([
    ["canned-tropical-fruits", "فواكه معلبة استوائية", "Canned Tropical Fruits"],
    ["syrups", "سيروبات", "Syrups"],
    ["fruit-purees", "فواكه مهروسة للحشوات", "Fruit Purees for Fillings"],
  ])("includes %s in both languages with its own image", async (id, ar, en) => {
    const products = await getProducts();
    const product = products.find(item => item.id === id);
    expect(product?.name).toEqual({ ar, en });
    expect(product?.image).toBeTruthy();
    expect(products.filter(item => item.image === product?.image)).toHaveLength(1);
  });
  it("never reuses product images", async () => {
    const products = await getProducts();
    expect(new Set(products.map(product => product.image)).size).toBe(products.length);
  });
});