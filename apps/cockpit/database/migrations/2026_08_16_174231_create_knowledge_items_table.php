<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('knowledge_items', function (Blueprint $table) {
            $table->id();
            $table->string('item_key', 190)->unique();
            $table->string('workflow_id', 160)->index();
            $table->string('feature_key', 160)->nullable();
            $table->string('title', 500);
            $table->string('subtitle', 500)->nullable();
            $table->string('status', 32)->default('pending');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('knowledge_items');
    }
};
