INSERT INTO users (
    id,
    email,
    password_hash,
    role,
    enabled,
    created_at,
    updated_at
)
VALUES (
           gen_random_uuid(),
           'devalex360@gmail.com',
           '{bcrypt}$2b$10$VZ.4NDD1L5839UpFjZlnUnGBXpK6ahPsr2TxKTUnogus3fjUwyCI3',
           'ADMIN',
           TRUE,
           NOW(),
           NOW()
       )
    ON CONFLICT (email)
DO UPDATE SET
    role = 'ADMIN',
           enabled = TRUE,
           updated_at = NOW();