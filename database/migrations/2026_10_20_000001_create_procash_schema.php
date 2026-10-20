<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Adopt existing Spring/Flyway tables without replacing their records or UUIDs.
        if (! Schema::hasTable('users')) {
            Schema::create('users', function (Blueprint $t) {
                $t->uuid('id')->primary();
                $t->string('email')->unique();
                $t->string('password_hash');
                $t->string('role', 30)->default('USER');
                $t->boolean('enabled')->default(true);
                $t->timestampsTz();
            });
        }
        if (! Schema::hasTable('restaurants')) {
            Schema::create('restaurants', function (Blueprint $t) {
                $t->uuid('id')->primary();
                $t->foreignUuid('owner_id')->constrained('users')->cascadeOnDelete();
                $t->string('name', 150);
                $t->string('slug', 150)->unique();
                $t->string('description', 1000)->nullable();
                $t->string('phone', 30)->nullable();
                $t->string('city', 100)->nullable();
                $t->string('status', 30)->default('DRAFT')->index();
                $t->boolean('active')->default(false);
                $t->timestampsTz();
            });
        }
        if (! Schema::hasTable('freedom_pay_applications')) {
            Schema::create('freedom_pay_applications', function (Blueprint $t) {
                $t->uuid('id')->primary();
                $t->foreignUuid('restaurant_id')->unique()->constrained()->cascadeOnDelete();
                $t->string('status', 30)->default('DRAFT')->index();
                $t->string('current_step', 30)->default('COMPANY');
                $t->string('organization_type', 50)->nullable();
                $t->string('company_name', 255)->nullable();
                $t->string('bin', 20)->nullable();
                $t->string('director_name', 255)->nullable();
                $t->string('director_iin', 20)->nullable();
                $t->string('director_phone', 30)->nullable();
                $t->string('director_email', 255)->nullable();
                $t->string('legal_address', 500)->nullable();
                $t->string('city', 100)->nullable();
                $t->string('postal_code', 20)->nullable();
                $t->string('iban', 50)->nullable();
                $t->string('bank_name', 255)->nullable();
                $t->string('bank_bic', 30)->nullable();
                $t->string('website_url', 500)->nullable();
                $t->string('business_category', 150)->nullable();
                $t->string('business_description', 1500)->nullable();
                $t->string('partner_application_id', 255)->nullable();
                $t->string('merchant_id', 255)->nullable();
                $t->decimal('average_check', 19, 2)->nullable();
                $t->decimal('expected_monthly_turnover', 19, 2)->nullable();
                $t->text('review_comment')->nullable();
                $t->timestampsTz();
            });
        }
        if (! Schema::hasTable('restaurant_tables')) {
            Schema::create('restaurant_tables', function (Blueprint $t) {
                $t->uuid('id')->primary();
                $t->foreignUuid('restaurant_id')->constrained()->cascadeOnDelete();
                $t->string('table_number', 50);
                $t->string('display_name', 150)->nullable();
                $t->uuid('qr_token')->unique();
                $t->boolean('active')->default(true);
                $t->timestampsTz();
                $t->unique(['restaurant_id', 'table_number']);
            });
        }
        if (! Schema::hasTable('restaurant_orders')) {
            Schema::create('restaurant_orders', function (Blueprint $t) {
                $t->uuid('id')->primary();
                $t->foreignUuid('restaurant_id')->constrained()->cascadeOnDelete();
                $t->foreignUuid('restaurant_table_id')->constrained()->cascadeOnDelete();
                $t->string('external_order_id')->nullable();
                $t->string('order_number', 100);
                $t->string('status', 30)->default('OPEN');
                $t->decimal('total_amount', 19, 2)->default(0);
                $t->timestampTz('opened_at');
                $t->timestampsTz();
            });
        }
        if (! Schema::hasTable('order_items')) {
            Schema::create('order_items', function (Blueprint $t) {
                $t->uuid('id')->primary();
                $t->foreignUuid('order_id')->constrained('restaurant_orders')->cascadeOnDelete();
                $t->string('name');
                $t->decimal('quantity', 10, 3)->default(1);
                $t->decimal('unit_price', 19, 2);
                $t->decimal('total_price', 19, 2);
                $t->timestampTz('created_at');
            });
        }
        if (! Schema::hasTable('payments')) {
            Schema::create('payments', function (Blueprint $t) {
                $t->uuid('id')->primary();
                $t->foreignUuid('order_id')->constrained('restaurant_orders')->cascadeOnDelete();
                $t->foreignUuid('restaurant_id')->constrained()->cascadeOnDelete();
                $t->decimal('amount', 19, 2);
                $t->string('status', 30);
                $t->string('provider', 30);
                $t->string('external_payment_id')->nullable();
                $t->timestampTz('paid_at')->nullable();
                $t->timestampsTz();
            });
        }
        if (! Schema::hasColumn('users', 'remember_token')) {
            Schema::table('users', fn (Blueprint $t) => $t->rememberToken());
        }
        if (! Schema::hasColumn('freedom_pay_applications', 'review_comment')) {
            Schema::table('freedom_pay_applications', fn (Blueprint $t) => $t->text('review_comment')->nullable());
        }
        foreach (['READY_TO_SUBMIT' => 'READY_FOR_REVIEW', 'SUBMITTED' => 'SUBMITTED_TO_FREEDOM', 'UNDER_REVIEW' => 'UNDER_FREEDOM_REVIEW'] as $old => $new) {
            DB::table('freedom_pay_applications')->where('status', $old)->update(['status' => $new]);
        }
    }

    public function down(): void
    {
        // These tables may predate Laravel. Never destroy adopted production data.
        throw new RuntimeException('Restore a database backup to roll back this schema adoption.');
    }
};
