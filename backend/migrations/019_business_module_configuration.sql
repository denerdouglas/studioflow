ALTER TABLE businesses
ADD COLUMN module_configuration JSONB;

COMMENT ON COLUMN businesses.module_configuration IS
  'Configuração explícita de módulos. NULL preserva a experiência completa de contas legadas.';
