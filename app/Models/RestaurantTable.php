<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

class RestaurantTable extends Model
{
    use HasUuids;

    protected $fillable = ['table_number', 'display_name'];

    protected $attributes = ['active' => true];

    protected static function booted(): void
    {
        static::creating(fn (self $table) => $table->qr_token ??= (string) Str::uuid());
    }

    protected function casts(): array
    {
        return ['active' => 'boolean'];
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(RestaurantOrder::class);
    }

    public function publicUrl(): string
    {
        return rtrim(config('procash.public_base_url'), '/').'/r/'.$this->restaurant->slug.'/q/'.$this->qr_token;
    }
}
