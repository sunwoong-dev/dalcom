-- 하드닝 검증: security definer 함수의 search_path, 테이블 권한
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

-- search_path에 pg_temp를 명시하지 않은 security definer 함수가 없어야 한다
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef
             and not exists (select 1 from unnest(p.proconfig) c where c = 'search_path=public, pg_temp')),
  0, 'definer_search_path_pins_pg_temp');

-- 앱 역할은 RLS를 우회하는 TRUNCATE와 TRIGGER·REFERENCES를 가지면 안 된다
select is((select count(*)::int from information_schema.role_table_grants
           where table_schema = 'public' and grantee in ('anon', 'authenticated')
             and privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')),
  0, 'no_truncate_trigger_references_grants');

-- 정상 권한은 남아 있다
select ok(has_table_privilege('authenticated', 'public.events', 'SELECT'), 'authenticated keeps select');
select ok(has_table_privilege('authenticated', 'public.events', 'INSERT'), 'authenticated keeps insert');
select ok(has_table_privilege('authenticated', 'public.events', 'UPDATE'), 'authenticated keeps update');
select ok(has_table_privilege('authenticated', 'public.events', 'DELETE'), 'authenticated keeps delete');
select ok(not has_table_privilege('anon', 'public.events', 'TRUNCATE'), 'anon cannot truncate');
select ok(not has_table_privilege('authenticated', 'public.events', 'TRUNCATE'), 'authenticated cannot truncate');

select * from finish();
rollback;
