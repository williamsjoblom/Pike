#pike __REAL_VERSION__

/* $Id$
 *
 * SSL Record Layer
 */

//! SSL Record Layer. Handle formatting and parsing of packets.


import .Constants;

constant SUPPORT_V2 = 1;

int content_type;
ProtocolVersion protocol_version;
string fragment;  /* At most 2^14 */

constant HEADER_SIZE = 5;

private string buffer;
private int needed_chars;

int marginal_size;

/* Circular dependence */
program Alert = master()->resolv("SSL")["alert"];
// #define Alert ((program) "alert")

void create(void|int extra)
{
  marginal_size = extra;
  buffer = "";
  needed_chars = HEADER_SIZE;
}

object check_size(ProtocolVersion version, int|void extra)
{
  marginal_size = extra;
  return (sizeof(fragment) > (PACKET_MAX_SIZE + extra))
    ? Alert(ALERT_fatal, ALERT_unexpected_message, version) : 0;
}

//! Receive data read from the network.
//!
//! @param data
//!   Raw data from the network.
//!
//! @param version
//!   Version of the SSL/TLS protocol suite to create a packet for.
//!
//! @returns
//!   Returns a string of leftover data if packet is complete,
//!   otherwise @expr{0@}.
//!
//!   If there's an error, an alert object is returned.
//!
object|string recv(string data, ProtocolVersion version)
{

#ifdef SSL3_FRAGDEBUG
  werror(" SSL.packet->recv: sizeof(data)="+sizeof(data)+"\n");
#endif 


  buffer += data;
  while (sizeof(buffer) >= needed_chars)
  {
    if (needed_chars == HEADER_SIZE)
    {
      content_type = buffer[0];
      int length;
      if (! PACKET_types[content_type] )
      {
	if (SUPPORT_V2)
	{
#ifdef SSL3_DEBUG
	  werror("SSL.packet: Receiving SSL2 packet %O\n", buffer[..4]);
#endif

	  content_type = PACKET_V2;
	  if ( (!(buffer[0] & 0x80)) /* Support only short SSL2 headers */
	       || (buffer[2] != 1))
	    return Alert(ALERT_fatal, ALERT_unexpected_message, version);
	  length = ((buffer[0] & 0x7f) << 8 | buffer[1]
		    - 3);
	  sscanf(buffer, "%*3c%2c", protocol_version);
	}
	else
	  return Alert(ALERT_fatal, ALERT_unexpected_message, version,
		       "SSL.packet->recv: invalid type\n", backtrace());
      } else {
	sscanf(buffer, "%*c%2c%2c", protocol_version, length);
	if ( (length <= 0) || (length > (PACKET_MAX_SIZE + marginal_size)))
	  return Alert(ALERT_fatal, ALERT_unexpected_message, version);
      }
      if ((protocol_version & ~0xff) != PROTOCOL_SSL_3_0)
	return Alert(ALERT_fatal, ALERT_unexpected_message, version,
		     sprintf("SSL.packet->send: Version %d.%d "
			     "is not supported\n",
			     protocol_version>>8, protocol_version & 0xff),
		     backtrace());
#ifdef SSL3_DEBUG
      if (protocol_version > PROTOCOL_TLS_MAX)
	werror("SSL.packet->recv: received version %d.%d packet\n",
	       protocol_version>>8, protocol_version & 0xff);
#endif

      needed_chars += length;
    } else {
      if (content_type == PACKET_V2)
	fragment = buffer[2 .. needed_chars - 1];
      else
	fragment = buffer[HEADER_SIZE .. needed_chars - 1];
      return buffer[needed_chars ..];
    }
  }
  return 0;
}

string send()
{
  if (! PACKET_types[content_type] )
    error( "Invalid type" );
  
  if ((protocol_version & ~0xff) != PROTOCOL_SSL_3_0)
    error( "Version %d is not supported\n", protocol_version>>8 );
#ifdef SSL3_DEBUG
  if (protocol_version > PROTOCOL_TLS_MAX)
    werror("SSL.packet->send: Sending version %d.%d packet\n",
	   protocol_version>>8, protocol_version & 0xff);
#endif
  if (sizeof(fragment) > (PACKET_MAX_SIZE + marginal_size))
    error( "Maximum packet size exceeded\n" );

  return sprintf("%c%2c%2c%s", content_type, protocol_version,
		 sizeof(fragment), fragment);
}