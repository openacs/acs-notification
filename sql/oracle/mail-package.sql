--------------------------------------------------
-- Wrapper procedures for utl_smtp, correcting
-- some of the bugs and providing utility functions
--------------------------------------------------

create or replace package mail
is

-- Open the connection and send "helo me"
function open_connection (
  --/** Open a mail connection, and prepare to identify the user
  --    @author Stanislav Freidin
  --    @param host          The hostname of the mailsrver, such as  
  --                         'mail.arsdigita.com'       
  --    @param port          The port on which the mailserver is expecting a
  --                         connection, usually 25
  --    @param mail_conn     The mail connection record. Information about
  --                         the opened connection will be returned here
  --    @return The reply code record from the mailserver. The expected reply
  --            code is 250.
  --    @see {mail.mail_from}, {mail.send_mail}, Oracle's utl_smtp package
  --*/
  host         IN varchar2, 
  port         IN pls_integer,
  mail_conn    OUT NOCOPY utl_smtp.connection
) return utl_smtp.reply;

-- Send the "mail from:" command
function mail_from (
  --/** Identify the user who is sending mail. <tt>open_connection</tt>
  --    must have been called previously
  --    @author Stanislav Freidin
  --    @param mail_conn     The mail connection object, created with
  --                         <tt>open_connection</tt>         
  --    @param email_from    The email of the user who is sending mail
  --    @return The reply code record from the mailserver. The expected reply
  --            code is 250.
  --    @see {mail.open_connection}, {mail.rcpt_to}, {mail.send_mail},
  --         Oracle's utl_smtp package
  --*/  
  mail_conn  IN OUT NOCOPY utl_smtp.connection,
  email_from IN varchar2
) return utl_smtp.reply;

-- Send the "rcpt to:" command; forward if neccessary
function rcpt_to (
  --/** Identify the recepient of the email. Automatically forward the
  --    mail if the recepient has a new address. <tt>mail_from</tt> must 
  --    have been called previously
  --    @author Stanislav Freidin
  --    @param mail_conn     The mail connection object, created with
  --                         <tt>open_connection</tt>         
  --    @param email_to      The email of the recepient of this email
  --    @return The reply code record from the mailserver. The expected reply
  --            codes are 250 or 251.
  --    @see {mail.open_connection}, {mail.open_data}, {mail.send_mail}, 
  --    Oracle's utl_smtp package
  --*/
  mail_conn  IN OUT NOCOPY utl_smtp.connection,
  email_to   IN varchar2
) return utl_smtp.reply;

-- Open up the data connection, preparing for the writing of data
function open_data (
  --/** Open the data connection, in preparation for sending headers
  --    and the body of the message
  --    @author Stanislav Freidin
  --    @param mail_conn     The mail connection object, created with
  --                         <tt>open_connection</tt>         
  --    @param email_to      The email of the recepient of this email
  --    @return The reply code record from the mailserver. The expected reply
  --            code is 250.
  --    @see {mail.open_connection}, {mail.write_data_headers}, {mail.send_mail}, 
  --    Oracle's utl_smtp package
  --*/
  mail_conn  IN OUT NOCOPY utl_smtp.connection
) return utl_smtp.reply;

-- Convert a date into email date format (GMT)
function to_email_date (
  --/** Convert an Oracle data into a string date compatible with email (GMT)
  --    @author Stanislav Freidin
  --    @param ora_date The date to convert
  --    @return         The converted string date
  --    @see {mai.write_data_headers}
  --*/
  ora_date IN date
) return varchar2;

-- Write outgoing headers (date:, to:, from:, subject)
procedure write_data_headers (
  --/** Write the email headers into the mail connection. <tt>open_data</tt>
  --    must have been called previously
  --    @author Stanislav Freidin
  --    @param mail_conn     The mail connection object, created with
  --                         <tt>open_connection</tt>
  --    @param email_from    The email of sender of this email         
  --    @param email_to      The email of the recepient of this email
  --    @param subject       A one-line subject for the message
  --    @param date_sent     The date when the message has been sent
  --    @see {mail.open_connection}, {mail.write_data_headers}, 
  --    {mail.write_data_clob}, {mail.write_data_string}, Oracle's utl_smtp package
  --*/
  mail_conn  IN OUT NOCOPY utl_smtp.connection,
  email_from IN varchar2,
  email_to   IN varchar2,
  subject    IN varchar2,
  date_sent  IN date default sysdate
);

-- Write a clob into the mail data connection, in chunks
procedure write_data_clob (
  --/** Write a clob into the mail data connection, in chunks of 3000 bytes.
  --    <tt>open_data</tt> must have been called prior to this point
  --    @author Stanislav Freidin
  --    @param mail_conn     The mail connection object, created with
  --                         <tt>open_connection</tt>         
  --    @param clob_loc      The clob whose contents will be written into
  --                         the connection
  --    @see {mail.open_connection}, {mail.write_data_headers}, 
  --    {mail.write_data_string}, {mail.send_mail}, Oracle's utl_smtp package
  --*/
  mail_conn IN OUT NOCOPY utl_smtp.connection,
  clob_loc  IN OUT NOCOPY clob
);

-- Write a string into the mail data connection
procedure write_data_string (
  --/** Write a string into the mail data connection.
  --    <tt>open_data</tt> must have been called prior to this point
  --    @author Stanislav Freidin
  --    @param mail_conn     The mail connection object, created with
  --                         <tt>open_connection</tt>         
  --    @param string_text   The string to be written into the connection
  --    @see {mail.open_connection}, {mail.write_data_headers}, 
  --    {mail.write_data_clob}, {mail.send_mail}, Oracle's utl_smtp package
  --*/
  mail_conn    IN OUT NOCOPY utl_smtp.connection,
  string_text  IN varchar2
);

-- Close the data connection
function close_data (
  --/** Close the data connection after all the text has been written into
  --    the body of the message
  --    <tt>open_data</tt> must have been called prior to this point
  --    @author Stanislav Freidin
  --    @param mail_conn     The mail connection object, created with
  --                         <tt>open_connection</tt>         
  --    @return The reply code record from the mailserver. The expected reply
  --            code is 250.
  --    @see {mail.open_data}, {mail.close_connection}, Oracle's utl_smtp package
  --*/
  mail_conn   IN OUT NOCOPY utl_smtp.connection
) return utl_smtp.reply;

-- Close the connection, finish mail session
procedure close_connection (
  --/** Close the mail connection, thus ending the mail sesssion
  --    @author Stanislav Freidin
  --    @param mail_conn     The mail connection object, created with
  --                         <tt>open_connection</tt>         
  --    @see {mail.open_connection}, Oracle's utl_smtp package
  --*/
  mail_conn  IN OUT NOCOPY utl_smtp.connection
);

-- A simple procedure to send and entire mail message
-- return 't' on success, 'f' on failure
function send_mail (
  --/** A simplified procedure to send a complete email message
  --    @author Stanislav Freidin
  --    @param email_from The sender's email
  --    @param email_to   The recepient's email
  --    @param subject    A one-line subject to be sent with the message
  --    @param text       The body of the message, 4000 characters maximum
  --    @param host       The hostname of the mailserver, such as 
  --                      'mail.arsdigita.com' 
  --    @param port       The port on which the mailserver expects a connection,
  --                      default 25
  --    @return 't' if the message was successfully sent, 'f' otherwise
  --    @see {mail.open_connection}
  --*/
  email_from IN varchar2,
  email_to   IN varchar2,
  subject    IN varchar2,
  text       IN varchar2,
  host       IN varchar2,
  port       IN pls_integer default 25
) return char;

end mail;
/
show errors

create or replace package body mail
is

function open_connection (
  host       IN varchar2, 
  port       IN pls_integer,
  mail_conn     OUT NOCOPY utl_smtp.connection
) return utl_smtp.reply
is
  v_mail_reply utl_smtp.reply;
begin

  v_mail_reply := utl_smtp.open_connection(host, port, mail_conn);
  if v_mail_reply.code <> 220 then
    return v_mail_reply;
  end if;

  return utl_smtp.helo(mail_conn, 'me');

end open_connection;


function mail_from (
  mail_conn  IN OUT NOCOPY utl_smtp.connection,
  email_from IN varchar2
) return utl_smtp.reply
is
  v_mail_reply utl_smtp.reply;
begin
  
  return utl_smtp.command(mail_conn, 'mail from:', email_from);

end;


function rcpt_to (
  mail_conn  IN OUT NOCOPY utl_smtp.connection,
  email_to IN varchar2
) return utl_smtp.reply
is
  v_mail_reply  utl_smtp.reply;
  v_email_to    varchar2(1000) := email_to;
  v_retry_count integer := 0;
begin

  for v_retry_count in 0..20 loop  

    begin
      v_mail_reply := utl_smtp.command(mail_conn, 'rcpt to:', v_email_to);
  
      if v_mail_reply.code <> 551 then
        return v_mail_reply;
      end if;

      -- Got the forwarding line, extract the email address and retry 
      if v_mail_reply.code = 551 then
        declare
          v_token_info str.token_info;
          v_token varchar2(1000);
          v_found char(1);
        begin
          v_token := str.first_token(v_mail_reply.text, v_token_info);
          v_found := 'f'; 

          while v_token is not null and v_found = 'f' loop
            if instr(v_token, '@') <> 0 then
              v_email_to := v_token;
              v_found := 't';
            end if;
            v_token := str.next_token(v_token_info);
          end loop;  

          -- If we could not extract the email, failure 
          if v_found = 'f' then
            return v_mail_reply;
          end if; 

        end;

      end if;

    exception
      when others then
      return v_mail_reply;
    end;  

  end loop;

  return v_mail_reply;

end;


function open_data (
  mail_conn  IN OUT NOCOPY utl_smtp.connection
) return utl_smtp.reply
is
begin
  return utl_smtp.open_data(mail_conn);
end open_data;
  

function to_email_date (
  ora_date IN date
) return varchar2
is
begin
  return initcap(to_char(ora_date, 'DY, DD MON YYYY HH24:MI:SS'));
end to_email_date;

procedure write_data_headers (
  mail_conn  IN OUT NOCOPY utl_smtp.connection,
  email_from IN varchar2,
  email_to   IN varchar2,
  subject    IN varchar2,
  date_sent  IN date default sysdate
)
is
  v_newline varchar2(20) := '
';
begin
  utl_smtp.write_data(mail_conn, 
    'Date: '   || to_email_date(date_sent) || v_newline ||
    'From: '   || email_from               || v_newline ||
    'To: '     || email_to                 || v_newline ||
    'Subject:' || subject                  || v_newline ||
    'Content-type: text/plain'             || v_newline ||
    v_newline 
  );
end write_data_headers;


procedure write_data_clob (
  mail_conn IN OUT NOCOPY utl_smtp.connection,
  clob_loc  IN OUT NOCOPY clob
)
is
  v_clob_length integer;
  v_string varchar2(4000);
  v_reply utl_smtp.reply;
  v_offset integer;
  v_amount integer;
begin
  
  v_clob_length := dbms_lob.getlength(clob_loc);
  v_offset := 1;
  
  while v_clob_length > 0 loop
    if v_clob_length < 3000 then
      v_amount := v_clob_length;
    else
      v_amount := 3000;
    end if;

    dbms_lob.read(clob_loc, v_amount, v_offset, v_string);
    utl_smtp.write_data(mail_conn, v_string);

    v_clob_length := v_clob_length - 3000;
    v_offset := v_offset + 3000;
  end loop;
end write_data_clob;

-- Write a string into the mail data connection
procedure write_data_string (
  mail_conn     IN OUT NOCOPY utl_smtp.connection,
  string_text   IN varchar2
)
is
begin
  utl_smtp.write_data(mail_conn, string_text);
end write_data_string;

function close_data (
  mail_conn  IN OUT NOCOPY utl_smtp.connection
) return utl_smtp.reply
is
begin
  return utl_smtp.close_data(mail_conn);
end close_data;


procedure close_connection (
  mail_conn  IN OUT NOCOPY utl_smtp.connection
)
is
begin
  utl_smtp.quit(mail_conn);
end close_connection;

-- A simple procedure to send and entire mail message
function send_mail (
  email_from IN varchar2,
  email_to   IN varchar2,
  subject    IN varchar2,
  text       IN varchar2,
  host       IN varchar2,
  port       IN pls_integer default 25
) return char
is
  v_reply utl_smtp.reply;
  v_mail_conn utl_smtp.connection;
begin  

  v_reply := open_connection(host, port, v_mail_conn);
  if v_reply.code <> 250 then
    return 'f';
  end if;

  v_reply := mail_from(v_mail_conn, email_from);
  if v_reply.code <> 250 then
    return 'f';
  end if;

  v_reply := rcpt_to(v_mail_conn, email_to);
  if v_reply.code not in (250, 251) then
    return 'f';
  end if;

  v_reply := open_data(v_mail_conn);
  write_data_headers(
    v_mail_conn, email_from, email_to, subject, sysdate
  );
  write_data_string(v_mail_conn, text);
  v_reply := close_data(v_mail_conn);
  if v_reply.code <> 250 then
    return 'f';
  end if;

  close_connection(v_mail_conn);

  return 't';
end send_mail;

end mail;
/
show errors







