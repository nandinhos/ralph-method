<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('feature_projections', function (Blueprint $table) {
            $table->id();
            $table->string('workflow_id', 160)->index();
            $table->string('feature_key', 160);
            $table->string('title', 500)->nullable();
            $table->unsignedInteger('position')->default(0);
            $table->string('status', 32)->default('pending');
            $table->string('engine', 80)->nullable();
            $table->unsignedInteger('attempt')->nullable();
            $table->unsignedInteger('duration_seconds')->nullable();
            $table->timestamps();
            $table->unique(['workflow_id', 'feature_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('feature_projections');
    }
};
