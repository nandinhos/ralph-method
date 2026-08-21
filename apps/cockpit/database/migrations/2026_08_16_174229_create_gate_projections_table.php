<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gate_projections', function (Blueprint $table) {
            $table->id();
            $table->string('workflow_id', 160);
            $table->string('feature_key', 160);
            $table->string('gate_key', 64);
            $table->string('status', 32)->default('pending');
            $table->string('detail', 500)->nullable();
            $table->timestamps();
            $table->index(['workflow_id', 'feature_key']);
            $table->unique(['workflow_id', 'feature_key', 'gate_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gate_projections');
    }
};
