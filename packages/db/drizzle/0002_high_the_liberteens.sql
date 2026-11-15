ALTER TABLE "chats" ADD COLUMN "description" text;--> statement-breakpoint
ALTER TABLE "chats" ADD COLUMN "username" text;--> statement-breakpoint
CREATE UNIQUE INDEX "chats_username_key" ON "chats" USING btree ("username");