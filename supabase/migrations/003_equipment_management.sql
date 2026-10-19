-- Existing installs: run this additive migration once. No Edge Function redeploy needed.
drop policy if exists groups_admin on public.groups;
create policy groups_admin on public.groups for all to authenticated
using (public.is_admin()) with check (public.is_admin());

-- Public equipment images contain no borrower information. Only admins can upload/change.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('equipment-images','equipment-images',true,1000000,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=1000000,
 allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists equipment_image_insert on storage.objects;
create policy equipment_image_insert on storage.objects for insert to authenticated
with check(bucket_id='equipment-images' and public.is_admin());
drop policy if exists equipment_image_update on storage.objects;
create policy equipment_image_update on storage.objects for update to authenticated
using(bucket_id='equipment-images' and public.is_admin())
with check(bucket_id='equipment-images' and public.is_admin());
drop policy if exists equipment_image_delete on storage.objects;
create policy equipment_image_delete on storage.objects for delete to authenticated
using(bucket_id='equipment-images' and public.is_admin());
