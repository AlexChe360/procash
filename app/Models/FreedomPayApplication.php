<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FreedomPayApplication extends Model
{
    use HasUuids;

    protected $fillable = ['organization_type', 'company_name', 'bin', 'director_name', 'director_iin', 'director_phone', 'director_email', 'legal_address', 'city', 'postal_code', 'iban', 'bank_name', 'bank_bic', 'website_url', 'business_category', 'business_description', 'average_check', 'expected_monthly_turnover'];

    protected $attributes = ['status' => 'DRAFT', 'current_step' => 'COMPANY'];

    protected function casts(): array
    {
        return ['average_check' => 'decimal:2', 'expected_monthly_turnover' => 'decimal:2'];
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    public function editable(): bool
    {
        return in_array($this->status, ['DRAFT', 'NEEDS_CHANGES'], true);
    }

    public function complete(): bool
    {
        foreach ($this->getFillable() as $field) {
            if (blank($this->$field)) {
                return false;
            }
        }

        return bccomp($this->average_check, '1', 2) >= 0 && bccomp($this->expected_monthly_turnover, '1', 2) >= 0;
    }
}
