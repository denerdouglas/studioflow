import sqlite3
import re

"""
FERRAMENTA DE VALIDAÇÃO DE SCHEMA (test_sqlite_schema.py)

Finalidade: Extrair as queries DDL do `database_schema.dart` e executá-las 
em um banco de dados SQLite temporário para validar sintaxe, integridade 
e regras de idempotência das migrations sem precisar iniciar o aplicativo Flutter.

- Usa banco descartável em memória (:memory:).
- Não acessa produção.
- Execução: `python tools/validation/test_sqlite_schema.py`
- Valida: Criação de tabelas, índices parciais (deleted_at), restrições 
  (CHECK, UNIQUE), ausência de regressões e constraints importantes (preço, saldo).
"""

def extract_sql():
    with open('lib/database/database_schema.dart', 'r', encoding='utf-8') as f:
        content = f.read()
    pattern = r"await db\.execute\('''([\s\S]*?)'''\);"
    return re.findall(pattern, content)

def main():
    print("--- 4. SQLite Banco Novo ---")
    conn = sqlite3.connect(':memory:')
    conn.execute("PRAGMA foreign_keys = OFF;")
    
    for stmt in extract_sql():
        try:
            conn.execute(stmt)
        except:
            pass
            
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]
    print(f"Tabelas criadas: {len(tables)}")
    
    print("\n--- 8. Checks Obrigatorios ---")
    
    try:
        conn.execute("INSERT INTO pacotes (id, business_id, nome, preco, status, created_at, updated_at) VALUES ('1', 'b', 'P', -10, 1, 'now', 'now')")
        print("FALHA: Preco negativo")
    except sqlite3.IntegrityError as e:
        print(f"SUCESSO: Preco negativo bloqueado. ({e})")
        
    try:
        conn.execute("INSERT INTO pacote_itens (id, pacote_id, servico_id, quantidade_sessoes, created_at, updated_at) VALUES ('pi1', '1', 's1', 0, 'now', 'now')")
        print("FALHA: Qtd sessoes 0")
    except sqlite3.IntegrityError as e:
        print(f"SUCESSO: Qtd sessoes 0 bloqueada. ({e})")

    try:
        conn.execute("INSERT INTO estoque_saldos (id, business_id, estoque_id, finalidade, local_id, created_at, updated_at) VALUES ('es1', 'b1', 'e1', 'venda', NULL, 'now', 'now')")
        conn.execute("INSERT INTO estoque_saldos (id, business_id, estoque_id, finalidade, local_id, created_at, updated_at) VALUES ('es2', 'b1', 'e1', 'venda', NULL, 'now', 'now')")
        print("FALHA: Saldo duplicado")
    except sqlite3.IntegrityError as e:
        print(f"SUCESSO: Saldo duplicado com local NULL bloqueado. ({e})")

    try:
        conn.execute("INSERT INTO whatsapp_fila (id, business_id, status, provider, idempotency_key, created_at, updated_at) VALUES ('w1', 'b1', 'fila', 'meta', 'idem1', 'now', 'now')")
        conn.execute("INSERT INTO whatsapp_fila (id, business_id, status, provider, idempotency_key, created_at, updated_at) VALUES ('w2', 'b1', 'fila', 'meta', 'idem1', 'now', 'now')")
        print("FALHA: Idemp key duplicada")
    except sqlite3.IntegrityError as e:
        print(f"SUCESSO: Idempotency key duplicada bloqueada. ({e})")

    print("\n--- 6. Idempotencia ---")
    try:
        for stmt in extract_sql():
            conn.execute(stmt)
        print("SUCESSO: DDL executado segunda vez sem erros destrutivos.")
    except Exception as e:
        print(f"FALHA na idempotencia: {e}")

if __name__ == '__main__':
    main()
