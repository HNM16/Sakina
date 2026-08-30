CREATE TYPE "public"."account_kind" AS ENUM('asset', 'liability', 'revenue', 'expense');--> statement-breakpoint
CREATE TYPE "public"."account_owner_type" AS ENUM('user', 'merchant', 'system');--> statement-breakpoint
CREATE TYPE "public"."ban_subject" AS ENUM('user', 'device');--> statement-breakpoint
CREATE TYPE "public"."chat_kind" AS ENUM('direct', 'group', 'channel');--> statement-breakpoint
CREATE TYPE "public"."entry_direction" AS ENUM('debit', 'credit');--> statement-breakpoint
CREATE TYPE "public"."identity_kind" AS ENUM('email', 'phone');--> statement-breakpoint
CREATE TYPE "public"."member_role" AS ENUM('owner', 'admin', 'member');--> statement-breakpoint
CREATE TYPE "public"."message_type" AS ENUM('text', 'media', 'voice', 'system', 'payment', 'service_card');--> statement-breakpoint
CREATE TYPE "public"."platform" AS ENUM('android', 'ios', 'web');--> statement-breakpoint
CREATE TYPE "public"."push_provider" AS ENUM('fcm', 'apns', 'none');--> statement-breakpoint
CREATE TYPE "public"."tx_status" AS ENUM('pending', 'completed', 'failed', 'reversed');--> statement-breakpoint
CREATE TYPE "public"."user_kind" AS ENUM('human', 'bot', 'service');--> statement-breakpoint
CREATE TABLE "bans" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"subject" "ban_subject" NOT NULL,
	"subject_id" uuid NOT NULL,
	"reason" text NOT NULL,
	"expires_at" timestamp with time zone,
	"created_by" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"lifted_at" timestamp with time zone,
	"lifted_reason" text
);
--> statement-breakpoint
CREATE TABLE "chat_members" (
	"chat_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"role" "member_role" DEFAULT 'member' NOT NULL,
	"read_up_to_seq" bigint DEFAULT 0 NOT NULL,
	"muted_until" timestamp with time zone,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	"left_at" timestamp with time zone,
	CONSTRAINT "chat_members_chat_id_user_id_pk" PRIMARY KEY("chat_id","user_id")
);
--> statement-breakpoint
CREATE TABLE "chats" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"kind" "chat_kind" NOT NULL,
	"title" text,
	"avatar_key" text,
	"last_seq" bigint DEFAULT 0 NOT NULL,
	"created_by" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "device_fingerprint_users" (
	"fingerprint_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "device_fingerprint_users_fingerprint_id_user_id_pk" PRIMARY KEY("fingerprint_id","user_id")
);
--> statement-breakpoint
CREATE TABLE "device_fingerprints" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"platform" "platform" NOT NULL,
	"fingerprint_hash" text NOT NULL,
	"source" text NOT NULL,
	"attested" boolean DEFAULT false NOT NULL,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "devices" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"platform" "platform" NOT NULL,
	"name" text DEFAULT 'unknown' NOT NULL,
	"push_token" text,
	"push_provider" "push_provider" DEFAULT 'none' NOT NULL,
	"push_failures" integer DEFAULT 0 NOT NULL,
	"push_disabled_at" timestamp with time zone,
	"last_seen_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revoked_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "identities" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"kind" "identity_kind" NOT NULL,
	"value" text NOT NULL,
	"canonical" text NOT NULL,
	"verified_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "invite_codes" (
	"code" text PRIMARY KEY NOT NULL,
	"created_by" uuid,
	"remaining_uses" integer DEFAULT 1 NOT NULL,
	"note" text,
	"expires_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "invite_redemptions" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"code" text NOT NULL,
	"user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ledger_accounts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_type" "account_owner_type" NOT NULL,
	"owner_id" uuid,
	"kind" "account_kind" NOT NULL,
	"currency" text DEFAULT 'TJS' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ledger_entries" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"transaction_id" uuid NOT NULL,
	"account_id" uuid NOT NULL,
	"direction" "entry_direction" NOT NULL,
	"amount_minor" bigint NOT NULL,
	"currency" text DEFAULT 'TJS' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ledger_transactions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"idempotency_key" text NOT NULL,
	"kind" text NOT NULL,
	"status" "tx_status" DEFAULT 'pending' NOT NULL,
	"external_ref" text,
	"provider" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "messages" (
	"chat_id" uuid NOT NULL,
	"seq" bigint NOT NULL,
	"id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"client_id" uuid NOT NULL,
	"sender_id" uuid NOT NULL,
	"type" "message_type" NOT NULL,
	"payload" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"edited_at" timestamp with time zone,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "messages_chat_id_seq_pk" PRIMARY KEY("chat_id","seq")
);
--> statement-breakpoint
CREATE TABLE "otp_codes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"kind" "identity_kind" NOT NULL,
	"canonical" text NOT NULL,
	"code_hash" text NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"consumed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"device_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"refresh_token_hash" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revoked_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "signup_attempts" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"device_id" uuid,
	"ip_hash" text,
	"canonical" text NOT NULL,
	"succeeded" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"username" text,
	"display_name" text NOT NULL,
	"avatar_key" text,
	"kind" "user_kind" DEFAULT 'human' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "bans" ADD CONSTRAINT "bans_created_by_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "chat_members" ADD CONSTRAINT "chat_members_chat_id_chats_id_fk" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "chat_members" ADD CONSTRAINT "chat_members_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "chats" ADD CONSTRAINT "chats_created_by_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_fingerprint_users" ADD CONSTRAINT "device_fingerprint_users_fingerprint_id_device_fingerprints_id_fk" FOREIGN KEY ("fingerprint_id") REFERENCES "public"."device_fingerprints"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_fingerprint_users" ADD CONSTRAINT "device_fingerprint_users_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "devices" ADD CONSTRAINT "devices_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "identities" ADD CONSTRAINT "identities_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "invite_codes" ADD CONSTRAINT "invite_codes_created_by_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "invite_redemptions" ADD CONSTRAINT "invite_redemptions_code_invite_codes_code_fk" FOREIGN KEY ("code") REFERENCES "public"."invite_codes"("code") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "invite_redemptions" ADD CONSTRAINT "invite_redemptions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ledger_entries" ADD CONSTRAINT "ledger_entries_transaction_id_ledger_transactions_id_fk" FOREIGN KEY ("transaction_id") REFERENCES "public"."ledger_transactions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ledger_entries" ADD CONSTRAINT "ledger_entries_account_id_ledger_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."ledger_accounts"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_chat_id_chats_id_fk" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_sender_id_users_id_fk" FOREIGN KEY ("sender_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "bans_subject_idx" ON "bans" USING btree ("subject","subject_id","lifted_at");--> statement-breakpoint
CREATE INDEX "chat_members_user_idx" ON "chat_members" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "device_fingerprint_users_user_idx" ON "device_fingerprint_users" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "device_fingerprints_key" ON "device_fingerprints" USING btree ("platform","fingerprint_hash");--> statement-breakpoint
CREATE INDEX "devices_user_idx" ON "devices" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "identities_canonical_key" ON "identities" USING btree ("kind","canonical");--> statement-breakpoint
CREATE INDEX "identities_user_idx" ON "identities" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "invite_codes_creator_idx" ON "invite_codes" USING btree ("created_by");--> statement-breakpoint
CREATE UNIQUE INDEX "invite_redemptions_user_key" ON "invite_redemptions" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "invite_redemptions_code_idx" ON "invite_redemptions" USING btree ("code");--> statement-breakpoint
CREATE UNIQUE INDEX "ledger_accounts_owner_key" ON "ledger_accounts" USING btree ("owner_type","owner_id","currency","kind");--> statement-breakpoint
CREATE INDEX "ledger_entries_tx_idx" ON "ledger_entries" USING btree ("transaction_id");--> statement-breakpoint
CREATE INDEX "ledger_entries_account_idx" ON "ledger_entries" USING btree ("account_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "ledger_tx_idempotency_key" ON "ledger_transactions" USING btree ("idempotency_key");--> statement-breakpoint
CREATE UNIQUE INDEX "messages_chat_client_key" ON "messages" USING btree ("chat_id","client_id");--> statement-breakpoint
CREATE UNIQUE INDEX "messages_id_key" ON "messages" USING btree ("id");--> statement-breakpoint
CREATE INDEX "otp_identity_idx" ON "otp_codes" USING btree ("kind","canonical","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "sessions_refresh_hash_key" ON "sessions" USING btree ("refresh_token_hash");--> statement-breakpoint
CREATE INDEX "sessions_device_idx" ON "sessions" USING btree ("device_id");--> statement-breakpoint
CREATE INDEX "signup_attempts_device_idx" ON "signup_attempts" USING btree ("device_id","created_at");--> statement-breakpoint
CREATE INDEX "signup_attempts_ip_idx" ON "signup_attempts" USING btree ("ip_hash","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "users_username_key" ON "users" USING btree ("username");