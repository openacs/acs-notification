------------------------------------------------
-- The procedures used by the notification module
------------------------------------------------

create or replace package nt
is

-- Post a new request, return its id
function post_request (
  --/** Post a notification request, which will be processed at a later
  --    time 
  --    @author Stanislav Freidin
  --    @param party_from    The id of the sending party
  --    @param party_to      The id of the sending party
  --    @param expand_group  If 't', the <tt>party_to</tt> is treated as a group
  --                         and an individual notification is sent to each member
  --                         of the group. If 'f', only one notification is sent
  --                         to the <tt>party_to</tt>'s email address.
  --    @param subject       A one-line subject for the message
  --    @param message       The body of the message, 4000 characters maximum
  --    @max_retries         The number of time to try before giving up on the
  --                         notification, defaults to 3
  --    @return The id of the new request
  --    @see {notification.cancel_request}
  --*/
  party_from   IN nt_requests.party_from%TYPE,
  party_to     IN nt_requests.party_to%TYPE,
  expand_group IN nt_requests.expand_group%TYPE,
  subject      IN nt_requests.subject%TYPE,
  message      IN varchar2,
  max_retries  IN nt_requests.max_retries%TYPE default 3
) return nt_requests.request_id%TYPE;

-- Cancel a request, marking all messages in the queue as failed
procedure cancel_request (
  --/** Cancel a notification requests. Mark all notifications that were generated
  --    by the request as Failed.
  --    @author Stanislav Freidin
  --    @param request_id    Id of the request to cancel
  --    @see {notification.post_request}
  --*/
  request_id IN nt_requests.request_id%TYPE
);

-- Flatten the pending requests into the notification queue, expanding
-- each target group to its individual members
procedure expand_requests
  --/** This is a helper procedure and is not part of the public API.
  --    It expands all pending requests, creating at least one row in
  --    <tt>nt_queue</tt> for each request.
  --    @author Stanislav Freidin
  --    @see {notification.post_request}
  --*/
;

-- Update the requests table to reflect the new status
-- * If all messages have failed, change status to "failed"
-- * If all messages have succeeded, change status to "sent"
-- * If some messages can still be retried, change status to "sending"
-- This is hideously inefficient - would it be better to include the
-- total_messages and sent_messages columns in the nt_requests table ?
procedure update_requests
  --/** This is a helper procedure and is not part of the public API.
  --    It updates all requests in the <tt>nt_requests</tt> table, setting
  --    the <tt>status</tt> as following: <ul>
  --    <li>If all messages have failed, change status to 'failed'</li>
  --    <li>If all messages have succeeded, change status to 'sent'</li>
  --    <li>If some messages have failed, but it is still possible to retry
  --        some messages, change status to 'sending'</li>
  --    <li>If some messages have failed, and it is not possible to retry
  --        any of them, set status to 'partial_failure'</li></ul>
  --    @author Stanislav Freidin
  --    @see {notification.expand_requests}, {notification.process_queue}
  --*/
;

-- This procedure will be run periodically by DBMS_JOB.
-- It will collect the pending requests, expand them if neccessary, and
-- then email them to the parties.
procedure process_queue (
  --/** This procedure will be run periodically, by <tt>dbms_job</tt>.
  --    The procedure will process the request queue, expand any pending
  --    requests, combine notifications with the same from/to parties,
  --    and send them out
  --    @author Stanislav Freidin
  --    @param host The hostname of the mailserver, such as 'mail.arsdigita.com'
  --    @param port The port on which the mailserver expects a connection,
  --                defaults to 25
  --    @see {notification.schedule_process}
  --*/
  host IN varchar2,
  port IN pls_integer default 25
);

-- Schedule the queue to be processed at a regular interval
-- The interval is the number of minutes between each job run
-- If the interval is null, cancels the job.
procedure schedule_process (
  --/** Schedule the processing of the queue at regular intervals. Shorter 
  --    intervals will mean more prompt processing of the requests, but may
  --    place too much strain on the server.
  --    @author Stanislav Freidin
  --    @param interval The number of minutes between processing of the queue. If
  --                    the interval is null, cancels processing of the queue
  --                    until <tt>schedule_process</tt> is called again with
  --                    a non-null interval
  --    @param host The hostname of the mailserver, such as 'mail.arsdigita.com'
  --    @param port The port on which the mailserver expects a connection,
  --                defaults to 25
  --    @see {notification.process_queue}
  --*/
  interval IN number,
  host     IN varchar2,
  port     IN integer default 25
);


end nt;
/
show errors

  
create or replace package body nt
is

     
function post_request (
  party_from   IN nt_requests.party_from%TYPE,
  party_to     IN nt_requests.party_to%TYPE,
  expand_group IN nt_requests.expand_group%TYPE,
  subject      IN nt_requests.subject%TYPE,
  message      IN varchar2,
  max_retries  IN nt_requests.max_retries%TYPE
) return nt_requests.request_id%TYPE
is
  v_clob_loc clob;
  v_id       nt_requests.request_id%TYPE;
begin

  select nt_request_seq.nextval into v_id from dual;

  insert into nt_requests
    (request_id, party_from, party_to, expand_group, 
     subject, message, status, max_retries)
  values
    (v_id, party_from, party_to, expand_group, 
     subject, empty_clob(), 'pending', max_retries)
  returning
    message into v_clob_loc;

  dbms_lob.writeappend(v_clob_loc, length(message), message);

  return v_id;

end post_request;

procedure cancel_request (
  request_id IN nt_requests.request_id%TYPE
) 
is
  v_max_retries nt_requests.max_retries%TYPE;
begin
  
  select max_retries + 1 into v_max_retries 
    from nt_requests where request_id = request_id;

  -- Set all the pending messages in the queue to failure
  update nt_queue set
    is_successful = 'f', retry_count = v_max_retries
  where
    request_id = request_id;

  update nt_requests set 
    status = 'cancelled'
  where
    request_id = request_id; 
end cancel_request;
     

procedure expand_requests
is
  cursor c_expanded_cur is
    select 
      r1.request_id, 
      NVL(m.member_id, r1.party_to) as party_to, 
      r1.request_date
    from
      nt_requests r1, group_approved_member_map m
    where
      r1.status = 'pending'
    and
      r1.expand_group = 't'
    and
      m.group_id(+) = r1.party_to
    union select
      r2.request_id,
      r2.party_to,
      r2.request_date
    from
      nt_requests r2
    where
      r2.status = 'pending'
    and
      r2.expand_group = 'f'     
    order by 
      request_date;

  c_request_row c_expanded_cur%ROWTYPE;

begin

  for c_request_row in c_expanded_cur loop
    insert into nt_queue 
      (request_id, party_to) 
    values 
      (c_request_row.request_id, c_request_row.party_to);
  end loop;

  -- Record the fact that these requests were expanded
  update nt_requests set status='sending' where status='pending';
end expand_requests;


procedure update_requests
is
begin 

  -- If there were no failures, request is successful
  update nt_requests set
    status = 'sent', fulfill_date = sysdate
  where
    status = 'sending' 
  and not exists
    (select 1 from nt_queue 
     where request_id = nt_requests.request_id 
     and is_successful = 'f');

  -- If there were no successes, and we gave up, request has failed
  update nt_requests set
    status = 'failed'
  where
    status = 'sending' 
  and not exists
    (select 1 from nt_queue 
     where request_id = nt_requests.request_id 
     and (is_successful = 't' or 
         (is_successful = 'f' and retry_count < nt_requests.max_retries)));

  -- If there were some successes, but we gave up, this is a partial failure
  update nt_requests set
    status = 'partial_failure', fulfill_date = sysdate
  where
    status = 'sending' 
  and exists
    (select 1 from nt_queue 
     where request_id = nt_requests.request_id 
     and is_successful = 't')
  and exists 
    (select 1 from nt_queue 
     where request_id = nt_requests.request_id 
     and (is_successful = 'f' and retry_count >= nt_requests.max_retries))
  and not exists
    (select 1 from nt_queue 
     where request_id = nt_requests.request_id 
     and (is_successful = 'f' and retry_count < nt_requests.max_retries));
 
end update_requests; 

procedure process_queue (
  host IN varchar2,
  port IN pls_integer default 25
)
is
  v_mail_conn utl_smtp.connection;
  v_mail_reply utl_smtp.reply;

  -- Cursor that loops through individual messages, processing them
  -- Only look at the messages which still have a chance of being sent out
  cursor c_queue_cur is
    select 
      q.party_to, q.retry_count, q.is_successful,
      r.party_from, r.message, r.subject, r.request_date,
      mail.to_email_date(r.request_date) as pretty_request_date, 
      r.max_retries, r.request_id,
      acs_object.name(q.party_to) name_to,
      pto.email as email_to,
      acs_object.name(r.party_from) name_from,
      pfrom.email as email_from
    from 
      nt_queue q, nt_requests r, parties pto, parties pfrom
    where
      q.is_successful <> 't'
    and
      q.request_id = r.request_id 
    and 
      pfrom.party_id = r.party_from
    and
      pto.party_id = q.party_to
    and
      pto.email is not null
    and
      q.retry_count < r.max_retries
    and 
      r.status = 'sending'
    order by
      r.party_from, q.party_to;

  c_queue_row c_queue_cur%ROWTYPE;

  v_old_party_from parties.party_id%TYPE := -1;
  v_old_party_to parties.party_id%TYPE := -1;
  v_ready_for_data char(1) := 'f';
  v_newline varchar2(10) := '
';

  message_failed exception;
  v_num_requests integer;

begin

  -- Record the time
  update nt_job set last_run_date = sysdate;
  
  -- Determine if we have anything to do
  select decode(count(*),0,0,1) into v_num_requests from nt_requests 
    where status in ('pending', 'sending');
  if v_num_requests < 1 then
    return;
  end if;

  -- Attempt to open connection, mark all items in the queue as failed
  -- if this could not be done
  begin
    v_mail_reply := mail.open_connection(host, port, v_mail_conn);
    if v_mail_reply.code <> 250 then
      raise_application_error(-20000, 'Unable to open connection to ' || host || ':' || port);
    end if;
  exception 
    when others then

    -- Update all pending requests to failure 
    update 
      nt_queue 
    set
      retry_count = retry_count + 1,
      smtp_reply_code = v_mail_reply.code,
      smtp_reply_message = v_mail_reply.text
    where
      is_successful = 'f' 
    and
      retry_count < (select max_retries from nt_requests
                     where request_id = nt_queue.request_id); 
    
    update_requests();

    begin 
      -- Just in case
      mail.close_connection(v_mail_conn);
    exception
      when others then null;
    end; 

    return;
  end;

  -- Expand the pending requests
  expand_requests();

  -- Now process individual rows, collecting their individual messages
  -- into a big chunk before sending the entire chunk

  for c_queue_row in c_queue_cur loop
  
    begin
 
      if v_ready_for_data = 't' and 
         (c_queue_row.party_from <> v_old_party_from or 
	  c_queue_row.party_to <> v_old_party_to) then
	  -- Close old connection, if any
	  v_mail_reply := mail.close_data(v_mail_conn);
	  v_ready_for_data := 'f';
      end if;

      -- Prepare to send data, if neccessary
      if v_ready_for_data <> 't' then

	-- Set up the sender
        if c_queue_row.email_from is not null then              
          v_mail_reply := mail.mail_from(v_mail_conn, c_queue_row.email_from);
        else
          v_mail_reply := mail.mail_from(v_mail_conn, 'unknown@unknown.com');
        end if;
	if v_mail_reply.code <> 250 then
          raise message_failed;
	end if;
	-- Set up the recepient
	v_mail_reply := mail.rcpt_to(v_mail_conn, c_queue_row.email_to);
	if v_mail_reply.code not in (250, 251) then
          raise message_failed;
	end if;
	-- Prepare to write data
	v_mail_reply := mail.open_data(v_mail_conn);

	-- Write headers
	mail.write_data_headers (
	  v_mail_conn, 
	  c_queue_row.email_from, c_queue_row.email_to, 
	  c_queue_row.subject, c_queue_row.request_date
	);

	v_ready_for_data := 't';

      end if;

      -- Once we have a working connection, write into it
      mail.write_data_string(
        v_mail_conn, 
        v_newline || v_newline ||'Message sent on ' || c_queue_row.pretty_request_date || 
        ' regarding ' || c_queue_row.subject || v_newline || v_newline);

      mail.write_data_clob(v_mail_conn, c_queue_row.message);

      -- Success: mark this entry and go on to the next one
      update nt_queue set 
	is_successful = 't' 
      where 
	request_id = c_queue_row.request_id
      and
	party_to = c_queue_row.party_to;

    exception 
      when utl_smtp.transient_error or 
           utl_smtp.permanent_error or 
           message_failed 
      then  

      -- Error sending mail: register that an error has occurred, go on to the next message
      update nt_queue set
        is_successful = 'f', retry_count = retry_count + 1,
        smtp_reply_code = v_mail_reply.code,
        smtp_reply_message = v_mail_reply.text
      where 
	request_id = c_queue_row.request_id
      and
	party_to = c_queue_row.party_to;

      -- Just in case, close the data connection
      if v_ready_for_data = 't' then
        v_mail_reply := mail.close_data(v_mail_conn);
        v_ready_for_data := 'f';
      end if;

    end;    

    v_old_party_from := c_queue_row.party_from;
    v_old_party_to := c_queue_row.party_to;

  end loop;

  -- Update the requests to reflect new status
  update_requests();

  if v_ready_for_data = 't' then
    v_mail_reply := mail.close_data(v_mail_conn);
  end if;

  mail.close_connection(v_mail_conn);
  
end process_queue;

procedure schedule_process (
  interval IN number,
  host IN varchar2,
  port IN integer default 25
)
is
  v_job_id integer := null;
begin
  
  -- Check if we have an existing job
  begin
    select job_id into v_job_id from nt_job;
  exception 
    when no_data_found then null;
  end;  

  -- Are we cancelling a job ?
  if interval is null then 
    if v_job_id is not null then
      dbms_job.remove(v_job_id);
      update nt_job set job_id = null; 
    end if;
  else
  -- We are inserting a new job or changing the interval
    if v_job_id is not null then
      dbms_job.remove(v_job_id);
    end if;
     
    dbms_job.submit(
      v_job_id, 
      'nt.process_queue(''' || host || ''', ' || port || ');',
      sysdate,
      'sysdate + ' || (interval/24/60),
      false,
      dbms_job.any_instance,
      true
    );

    update nt_job set job_id = v_job_id, last_run_date = null;

  end if;

end schedule_process;  

end nt;
/
show errors;



