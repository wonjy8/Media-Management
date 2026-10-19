-- Run in a local/test database after 010. All fixture changes roll back.
begin;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$select true$$;
insert into equipment(id,code,name,quantity) values
 ('91000000-0000-0000-0000-000000000001',null,'번호 없는 케이블A',5),
 ('91000000-0000-0000-0000-000000000002','','번호 없는 케이블B',5),
 ('91000000-0000-0000-0000-000000000003',' TEST-CAM-01 , TEST-CAM-02, ','여러 대 카메라',2);
do $$begin
 if (select count(*) from equipment where id in ('91000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000002') and code is null)<>2 then raise exception 'blank codes not nullable';end if;
 if (select code from equipment where id='91000000-0000-0000-0000-000000000003')<>'TEST-CAM-01, TEST-CAM-02' then raise exception 'multiple code normalization failed';end if;
 begin
  update equipment set code='TEST-NEW-01, TEST-CAM-02' where id='91000000-0000-0000-0000-000000000001';
  raise exception 'overlapping code accepted';
 exception when unique_violation then null;end;
 if (select code from equipment where id='91000000-0000-0000-0000-000000000001') is not null then raise exception 'failed write not rolled back';end if;
 if exists(select 1 from equipment_management_codes where code='TEST-NEW-01') then raise exception 'failed index write not rolled back';end if;
end $$;
select admin_save_equipment_with_accessories(
 '{"code":null,"name":"카메라 번호 제거","quantity":2,"repair_quantity":0,"active":true}',
 '[]','91000000-0000-0000-0000-000000000003');
update equipment set code='TEST-CAM-01' where id='91000000-0000-0000-0000-000000000001';
do $$begin
 if (select count(*) from equipment_management_codes where equipment_id='91000000-0000-0000-0000-000000000003')<>0 then raise exception 'stale code index';end if;
 if not exists(select 1 from equipment_management_codes where equipment_id='91000000-0000-0000-0000-000000000001' and code='TEST-CAM-01') then raise exception 'released code cannot be reused';end if;
end $$;
rollback;
