"""Business metrics exposed at /metrics alongside the automatic HTTP metrics."""

from prometheus_client import Counter

ORDERS_PLACED = Counter("freshmart_orders_placed_total", "Orders successfully placed")
ORDER_REVENUE = Counter("freshmart_order_revenue_dollars_total", "Revenue from placed orders, in USD")
ORDER_ITEMS = Counter("freshmart_order_items_total", "Units sold across placed orders")
ORDERS_CANCELLED = Counter(
    "freshmart_orders_cancelled_total", "Orders cancelled", ["cancelled_by"]
)
CHECKOUT_FAILURES = Counter(
    "freshmart_checkout_failures_total", "Checkouts rejected", ["reason"]
)
