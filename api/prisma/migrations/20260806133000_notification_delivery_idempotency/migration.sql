WITH ranked_deliveries AS (
  SELECT
    "id",
    ROW_NUMBER() OVER (
      PARTITION BY "notificationId", "subscriptionId"
      ORDER BY "createdAt" ASC, "id" ASC
    ) AS row_number
  FROM "NotificationDelivery"
  WHERE "subscriptionId" IS NOT NULL
)
DELETE FROM "NotificationDelivery"
WHERE "id" IN (
  SELECT "id"
  FROM ranked_deliveries
  WHERE row_number > 1
);

CREATE UNIQUE INDEX "NotificationDelivery_notificationId_subscriptionId_key"
ON "NotificationDelivery"("notificationId", "subscriptionId");
