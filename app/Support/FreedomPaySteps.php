<?php

namespace App\Support;

class FreedomPaySteps
{
    public const STEPS = ['company' => 'Компания', 'director' => 'Руководитель', 'address' => 'Адрес', 'bank' => 'Банк', 'restaurant' => 'Ресторан', 'review' => 'Проверка'];

    public static function fields(string $step): array
    {
        return match ($step) {
            'company' => ['organization_type' => 'Форма организации', 'company_name' => 'Наименование компании', 'bin' => 'БИН / ИИН'],
            'director' => ['director_name' => 'ФИО руководителя', 'director_iin' => 'ИИН руководителя', 'director_phone' => 'Телефон руководителя', 'director_email' => 'Email руководителя'],
            'address' => ['legal_address' => 'Юридический адрес', 'city' => 'Город', 'postal_code' => 'Почтовый индекс'],
            'bank' => ['iban' => 'IBAN', 'bank_name' => 'Название банка', 'bank_bic' => 'БИК'],
            'restaurant' => ['website_url' => 'Сайт ресторана', 'business_category' => 'Категория бизнеса', 'business_description' => 'Описание деятельности', 'average_check' => 'Средний чек, ₸', 'expected_monthly_turnover' => 'Ожидаемый месячный оборот, ₸'],
            default => [],
        };
    }

    public static function rules(string $step): array
    {
        return match ($step) {
            'company' => ['organization_type' => ['required', 'string', 'max:50'], 'company_name' => ['required', 'string', 'max:255'], 'bin' => ['required', 'digits:12']],
            'director' => ['director_name' => ['required', 'string', 'max:255'], 'director_iin' => ['required', 'digits:12'], 'director_phone' => ['required', 'regex:/^\+?[0-9 ()-]{10,20}$/'], 'director_email' => ['required', 'email', 'max:255']],
            'address' => ['legal_address' => ['required', 'string', 'max:500'], 'city' => ['required', 'string', 'max:100'], 'postal_code' => ['required', 'digits:6']],
            'bank' => ['iban' => ['required', 'regex:/^KZ\d{2}[A-Z0-9]{16}$/'], 'bank_name' => ['required', 'string', 'max:255'], 'bank_bic' => ['required', 'regex:/^[A-Z0-9]{8,11}$/']],
            'restaurant' => ['website_url' => ['required', 'url:http,https', 'max:500'], 'business_category' => ['required', 'string', 'max:150'], 'business_description' => ['required', 'string', 'min:20', 'max:1500'], 'average_check' => ['required', 'numeric', 'min:1', 'max:99999999999999999.99', 'decimal:0,2'], 'expected_monthly_turnover' => ['required', 'numeric', 'min:1', 'max:99999999999999999.99', 'decimal:0,2']],
            default => [],
        };
    }
}
