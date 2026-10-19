-- Run on a local/test database after 009 with ON_ERROR_STOP=1. All changes roll back.
begin;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(current_setting('test.accessory_admin',true),'false')='true'
$$;
set local test.accessory_admin='true';
insert into equipment(id,code,name,quantity) values
 ('90000000-0000-0000-0000-000000000001','ACCESSORY-TEST-CAMERA','카메라',2),
 ('90000000-0000-0000-0000-000000000002','ACCESSORY-TEST-SPEAKER','스피커',2),
 ('90000000-0000-0000-0000-000000000003','ACCESSORY-TEST-CABLE','공용 충전선',2);
select admin_save_equipment_with_accessories(
 '{"code":"ACCESSORY-TEST-CAMERA","name":"카메라","quantity":2,"repair_quantity":0,"active":true}',
 '[{"id":"90000000-0000-0000-0000-000000000003","quantity":1,"selectedByDefault":true}]',
 '90000000-0000-0000-0000-000000000001');
select admin_save_equipment_with_accessories(
 '{"code":"ACCESSORY-TEST-SPEAKER","name":"스피커","quantity":2,"repair_quantity":0,"active":true}',
 '[{"id":"90000000-0000-0000-0000-000000000003","quantity":2,"selectedByDefault":false}]',
 '90000000-0000-0000-0000-000000000002');
do $$begin
 if (select count(*) from equipment_accessories where accessory_id='90000000-0000-0000-0000-000000000003')<>2 then raise exception 'shared accessory missing';end if;
 begin
  perform admin_save_equipment_with_accessories(
   '{"code":"ACCESSORY-TEST-CAMERA","name":"잘못된 변경","quantity":2,"repair_quantity":0,"active":true}',
   '[{"id":"90000000-0000-0000-0000-000000000001","quantity":1,"selectedByDefault":true}]',
   '90000000-0000-0000-0000-000000000001');
  raise exception 'self link accepted';
 exception when others then if sqlerrm='self link accepted' then raise;end if;end;
 if (select name from equipment where id='90000000-0000-0000-0000-000000000001')<>'카메라' or
 (select count(*) from equipment_accessories where equipment_id='90000000-0000-0000-0000-000000000001')<>1 then raise exception 'failed save was not atomic';end if;
end $$;
set local role anon;
set local test.accessory_admin='false';
do $$begin
 if (select count(*) from equipment_accessories where accessory_id='90000000-0000-0000-0000-000000000003')<>2 then raise exception 'public active links missing';end if;
 begin
  delete from equipment_accessories;
  raise exception 'anonymous modification accepted';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
set local test.accessory_admin='true';
update equipment set active=false where id='90000000-0000-0000-0000-000000000003';
set local role anon;
set local test.accessory_admin='false';
do $$begin
 if exists(select 1 from equipment_accessories where accessory_id='90000000-0000-0000-0000-000000000003') then raise exception 'inactive accessory exposed';end if;
end $$;
reset role;
set local test.accessory_admin='true';
delete from equipment where id='90000000-0000-0000-0000-000000000003';
do $$begin
 if exists(select 1 from equipment_accessories where accessory_id='90000000-0000-0000-0000-000000000003') then raise exception 'deleted accessory links remain';end if;
end $$;
rollback;
