import type { Product } from "../types";

const CATEGORY_EMOJI: Record<string, string> = {
  fruits: "🍎",
  vegetables: "🥦",
  "dairy-eggs": "🥛",
  bakery: "🥖",
  pantry: "🥫",
};

export default function ProductImage({ product, size = "md" }: { product: Product; size?: "sm" | "md" }) {
  return (
    <div className={`product-image product-image-${size}`}>
      {product.image_url ? (
        <img src={product.image_url} alt={product.name} loading="lazy" />
      ) : (
        <span aria-hidden="true">{CATEGORY_EMOJI[product.category.slug] ?? "🛒"}</span>
      )}
    </div>
  );
}
