"""Initial wholesale prices (USD) and packages per product.

Prices are realistic market estimates for 2026 and are meant to be edited from
the admin app. Format per product: (price per unit, unit, [packages], discount %).
Each package is (size, container). Bigger packages get a lower unit price.
"""

# container: (Arabic, English)
BAG = ("كيس", "Bag")
BOX = ("كرتونة", "Box")
TUB = ("سطل", "Tub")
TIN = ("تنكة", "Tin")
DRUM = ("برميل", "Drum")
BOTTLE = ("عبوة", "Bottle")
JAR = ("علبة", "Jar")

P = {
    # Chocolate & cocoa
    "natural-cocoa": (8.5, "kg", [(5, BAG), (25, BAG)], 0),
    "alkalized-cocoa": (9.5, "kg", [(5, BAG), (25, BAG)], 10),
    "cocoa-butter": (18.0, "kg", [(5, BOX), (25, BOX)], 0),
    "cocoa-mass": (12.0, "kg", [(5, BOX), (25, BOX)], 0),
    "dark-couverture": (11.0, "kg", [(5, BAG), (10, BOX)], 0),
    "milk-couverture": (10.0, "kg", [(5, BAG), (10, BOX)], 8),
    "white-couverture": (10.5, "kg", [(5, BAG), (10, BOX)], 0),
    "chocolate-chips": (7.0, "kg", [(5, BAG), (10, BOX)], 0),
    # Nuts & seeds
    "hazelnuts": (11.0, "kg", [(1, BAG), (10, BOX)], 0),
    "pistachios": (26.0, "kg", [(1, BAG), (10, BOX)], 0),
    "almonds": (9.0, "kg", [(1, BAG), (10, BOX)], 12),
    "cashews": (10.0, "kg", [(1, BAG), (10, BOX)], 0),
    "walnuts": (9.0, "kg", [(1, BAG), (10, BOX)], 0),
    "peanuts": (3.0, "kg", [(5, BAG), (25, BAG)], 0),
    "nut-paste": (9.0, "kg", [(1, JAR), (5, TUB)], 0),
    "sesame": (2.6, "kg", [(5, BAG), (25, BAG)], 0),
    # Dried fruits
    "dried-apricots": (7.5, "kg", [(1, BAG), (10, BOX)], 0),
    "raisins": (3.2, "kg", [(1, BAG), (10, BOX)], 10),
    "dried-dates": (3.0, "kg", [(1, BAG), (10, BOX)], 0),
    "dried-figs": (6.5, "kg", [(1, BAG), (10, BOX)], 0),
    "dried-cranberries": (6.0, "kg", [(1, BAG), (10, BOX)], 0),
    "coconut-flakes": (4.5, "kg", [(1, BAG), (25, BAG)], 0),
    # Bakery & confectionery
    "bakery-base-mix": (2.2, "kg", [(10, BAG), (25, BAG)], 0),
    "bread-improver": (4.5, "kg", [(1, BAG), (10, BOX)], 0),
    "baking-powder": (2.5, "kg", [(1, BAG), (25, BAG)], 0),
    "dry-yeast": (5.5, "kg", [(0.5, BAG), (10, BOX)], 0),
    "corn-starch": (1.1, "kg", [(1, BAG), (25, BAG)], 0),
    "chocolate-filling": (4.8, "kg", [(5, TUB), (12, TUB)], 7),
    "fruit-filling": (3.8, "kg", [(5, TUB), (12, TUB)], 0),
    "neutral-glaze": (4.2, "kg", [(5, TUB), (14, TUB)], 0),
    "sprinkles": (5.0, "kg", [(1, JAR), (5, BOX)], 0),
    "fruit-purees": (4.0, "kg", [(1, TUB), (5, TUB)], 0),
    # Ice cream & dairy
    "icecream-base": (6.0, "kg", [(1, BAG), (25, BAG)], 0),
    "milk-powder": (4.2, "kg", [(1, BAG), (25, BAG)], 0),
    "whey-powder": (2.4, "kg", [(25, BAG)], 0),
    "cream-powder": (6.5, "kg", [(1, BAG), (25, BAG)], 0),
    "soft-serve-mix": (5.5, "kg", [(1, BAG), (10, BOX)], 10),
    # Flavors & colors
    "vanilla-flavor": (22.0, "l", [(1, BOTTLE), (5, BOTTLE)], 0),
    "strawberry-flavor": (18.0, "l", [(1, BOTTLE), (5, BOTTLE)], 0),
    "caramel-flavor": (18.0, "l", [(1, BOTTLE), (5, BOTTLE)], 0),
    "food-colors": (25.0, "kg", [(0.5, JAR), (1, JAR)], 0),
    # Oils & fats
    "palm-oil": (1.6, "kg", [(18, TIN)], 0),
    "bakery-shortening": (2.1, "kg", [(15, BOX)], 0),
    "industrial-margarine": (2.3, "kg", [(10, BOX)], 0),
    "cocoa-butter-substitute": (3.8, "kg", [(25, BOX)], 0),
    "coconut-oil": (2.6, "kg", [(18, TIN)], 0),
    # Sugars & sweeteners
    "white-sugar": (0.75, "kg", [(10, BAG), (50, BAG)], 0),
    "glucose-syrup": (1.0, "kg", [(25, TUB), (300, DRUM)], 0),
    "dextrose": (1.1, "kg", [(25, BAG)], 0),
    "invert-sugar": (1.2, "kg", [(25, TUB)], 0),
    "sorbitol": (1.8, "kg", [(25, TUB)], 0),
    "syrups": (4.5, "l", [(1, BOTTLE), (5, BOTTLE)], 0),
    # Stabilizers & emulsifiers
    "lecithin": (3.5, "kg", [(1, JAR), (20, TUB)], 0),
    "mono-diglycerides": (4.0, "kg", [(1, BAG), (25, BAG)], 0),
    "xanthan-gum": (6.5, "kg", [(1, BAG), (25, BOX)], 0),
    "guar-gum": (4.5, "kg", [(1, BAG), (25, BAG)], 0),
    "pectin": (18.0, "kg", [(1, BAG), (25, BOX)], 0),
    "carrageenan": (14.0, "kg", [(1, BAG), (25, BOX)], 0),
    "cmc": (5.0, "kg", [(1, BAG), (25, BAG)], 0),
    # General
    "maltodextrin": (1.3, "kg", [(25, BAG)], 0),
    "citric-acid": (1.6, "kg", [(1, BAG), (25, BAG)], 0),
    "sodium-bicarbonate": (0.9, "kg", [(1, BAG), (25, BAG)], 0),
    "food-grade-salt": (0.35, "kg", [(25, BAG), (50, BAG)], 0),
    "potassium-sorbate": (6.0, "kg", [(1, BAG), (25, BOX)], 0),
    "sodium-benzoate": (2.5, "kg", [(1, BAG), (25, BAG)], 0),
    "canned-tropical-fruits": (2.2, "kg", [(3, TIN), (18, BOX)], 0),
}

UNIT_TEXT = {"kg": ("كغ", "kg"), "l": ("لتر", "L")}
FEATURED_EXTRA = {"pistachios", "milk-couverture", "vanilla-flavor", "dried-apricots"}


def _fmt(n):
    return f"{n:g}"


def packages(product_id):
    """Return a list of dicts ready for Variant(**...)."""
    unit_price, unit, packs, discount = P[product_id]
    unit_ar, unit_en = UNIT_TEXT[unit]
    result = []
    seed = sum(ord(c) for c in product_id)
    for index, (size, (cont_ar, cont_en)) in enumerate(packs):
        # 1 kg packs cost ~6% more per kg; 25 kg+ packs ~5% less
        factor = 1.06 if size <= 1 else (0.95 if size >= 25 else 1.0)
        price = round(unit_price * size * factor, 2)
        stock = 20 + (seed * (index + 3)) % 180
        if product_id in ("cocoa-mass", "pectin"):
            stock = 4 + index  # a few low-stock items so the dashboard alert can be tested
        if product_id == "dried-figs" and index == 0:
            stock = 0
        if product_id == "canned-tropical-fruits" and size == 18:
            label_ar, label_en = "كرتونة 6 علب × 3 كغ", "Box of 6 × 3 kg tins"
        else:
            label_ar = f"{cont_ar} {_fmt(size)} {unit_ar}"
            label_en = f"{_fmt(size)} {unit_en} {cont_en.lower()}"
        result.append(
            {
                "label_ar": label_ar,
                "label_en": label_en,
                "unit": unit,
                "unit_quantity": size,
                "sku": f"{product_id[:12].upper()}-{_fmt(size).replace('.', '_')}",
                "price": price,
                "discount_price": round(price * (100 - discount) / 100, 2) if discount else None,
                "stock": stock,
                "min_order_qty": 5 if size <= 1 else 1,
                "sort_order": index,
            }
        )
    return result
