<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ingest_cursors', function (Blueprint $table) {
            $table->id();
            $table->string('source_key', 64)->unique();
            $table->unsignedBigInteger('byte_offset')->default(0);
            $table->string('last_hash', 64)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ingest_cursors');
    }
};
