<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('workflow_projections', function (Blueprint $table) {
            $table->id();
            $table->string('workflow_id', 160)->unique();
            $table->string('branch', 255)->nullable();
            $table->string('health', 32)->default('unknown');
            $table->string('state', 64)->nullable();
            $table->string('cursor_feature_key', 160)->nullable();
            $table->unsignedTinyInteger('progress_percent')->default(0);
            $table->string('engine', 80)->nullable();
            $table->unsignedInteger('attempt')->nullable();
            $table->unsignedInteger('recovery_count')->default(0);
            $table->timestamp('started_at')->nullable();
            $table->timestamp('last_event_at')->nullable();
            $table->json('monitor_payload')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('workflow_projections');
    }
};
