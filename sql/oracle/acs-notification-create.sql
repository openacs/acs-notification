----------------------------------------------------------
-- Create the notification data model, which supports the
-- message queue.
----------------------------------------------------------


-- The notification queue which holds all the notification requests,
-- pending or processed

create table nt_requests (
  -- Unique request id
  request_id    integer           constraint nt_request_pk
                                  primary key,
  -- The party to whom this message is being sent
  party_to      integer not null  constraint nt_request_party_to_ref
		                  references parties,
  -- If the target party is a group, do we completely flatten 
  -- it, thus sending email to individual users, or do we send the
  -- email to the group if it has an email address ?
  expand_group char(1) default 'f' not null
    constraint nt_request_expand_chk check(expand_group in ('t', 'f')),
  -- The party who is sending this message
  -- Doesn't really have to have an email field... ?
  party_from    integer not null  constraint nt_request_party_from_ref
		                  references parties,
  -- The message that will be sent
  message       clob,
  -- One line of subject text for the message
  subject       varchar2(1000),
  -- The date on which the posting to the queue was made
  request_date  date              default sysdate,
  -- The date on which the request was fulfilled
  fulfill_date  date,             
  -- The status of the request 
  -- pending: no attempt made to send it yet
  -- sent:    sent successfully
  -- partial: an attempt to send the request has been made, but not all of 
  --          the users in the target group have been reached
  -- partial_sent: some of the messages went through, others we gave up on
  -- failed:  check the error_code and error_message columns
  -- cancelled: request was aborted  
  status        varchar2(20)      default 'pending' 
                                  constraint nt_request_status_chk
  check(status in ('pending', 'sent', 'sending', 'partial_failure', 'failed', 'cancelled')),
  -- How many times will we try to send this message ?
  max_retries integer default 3   not null 
);

create sequence nt_request_seq start with 1000;

create index nt_request_expand_idx on nt_requests
  (expand_group, request_date, party_to);

create index nt_requests_party_to_idx on nt_requests (party_to);
create index nt_requests_party_from_idx on nt_requests (party_from);

-- The table that holds all the neccessary SMTP information for individual
-- users

create table nt_queue (
  -- Request id
  request_id    integer           constraint nt_queue_request_ref
		                  references nt_requests on delete cascade,                               
  -- The individual user to whom email is being sent
  -- Not neccessarily the same as nt_requests.party_id
  party_to      integer           constraint nt_queue_party_to_ref
                                  references parties on delete cascade,
  -- Composite primary key
  primary key(request_id, party_to),
  -- SMTP reply code (250 means ok)
  smtp_reply_code integer,
  -- SMTP text reply message
  smtp_reply_message varchar2(4000),
  -- How many times have we already tried to send this message ?
  retry_count   integer default 0 not null,
  -- Did we succeed in sending this message ?
  -- This is really just syntactic sugar, since we can just look at the 
  -- smtp_reply_code
  is_successful char(1) default 'f' not null
    constraint nt_queue_is_successful_chk 
    check (is_successful in ('t', 'f'))
);

create index nt_queue_success_idx on nt_queue
  (request_id, is_successful, retry_count);

-- This table keeps track of the job id for scheduling the queue
-- processing, and some miscellaneous statisticc

create table nt_job (
  job_id        integer,
  last_run_date date
);

insert into nt_job (job_id, last_run_date) values (null, null);

-- Make sure that only one value can exist in the nt_job table
create or replace trigger nt_job_tr
before insert or delete on nt_job
begin 
  raise_application_error(-20000,
    'Table nt_job must have exactly one row.'
  );
end;
/
show errors

prompt *** Compiling mail utility package...
@@ mail-package.sql
prompt *** Compiling notification package...
@@ acs-notification-package.sql
