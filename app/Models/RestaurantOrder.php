<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class RestaurantOrder extends Model
{
    use HasUuids;

    protected $fillable = ['restaurant_id', 'restaurant_table_id', 'external_order_id', 'order_number', 'status', 'total_amount', 'opened_at'];

    protected $attributes = ['status' => 'OPEN', 'total_amount' => '0.00'];

    protected function casts(): array
    {
        return ['total_amount' => 'decimal:2', 'opened_at' => 'datetime'];
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    public function table(): BelongsTo
    {
        return $this->belongsTo(RestaurantTable::class, 'restaurant_table_id');
    }

    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class, 'order_id');
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class, 'order_id');
    }
}
