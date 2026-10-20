<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

class User extends Authenticatable
{
    use HasFactory, HasUuids, Notifiable;

    protected $fillable = ['email', 'password_hash', 'role', 'enabled'];

    protected $hidden = ['password_hash', 'remember_token'];

    protected $attributes = ['role' => 'USER', 'enabled' => true];

    protected function casts(): array
    {
        return ['enabled' => 'boolean'];
    }

    public function getAuthPasswordName(): string
    {
        return 'password_hash';
    }

    public function getAuthPassword(): string
    {
        $hash = $this->password_hash;
        if (str_starts_with($hash, '{bcrypt}')) {
            $hash = substr($hash, 8);
        }

        return str_starts_with($hash, '$2a$') ? '$2y$'.substr($hash, 4) : $hash;
    }

    public function restaurants(): HasMany
    {
        return $this->hasMany(Restaurant::class, 'owner_id');
    }

    public function isAdmin(): bool
    {
        return $this->enabled && $this->role === 'ADMIN';
    }
}
