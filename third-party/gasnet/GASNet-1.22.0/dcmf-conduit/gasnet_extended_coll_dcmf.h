/*   $Source: /var/local/cvs/gasnet/dcmf-conduit/gasnet_extended_coll_dcmf.h,v $
 *     $Date: 2013/06/07 19:27:56 $
 * $Revision: 1.10 $
 * Description: GASNet extended collectives implementation on DCMF
 * Copyright 2009, E. O. Lawrence Berekely National Laboratory
 * Terms of use are as specified in license.txt
 */

#ifndef GASNET_EXTENDED_COLL_DCMF_H_
#define GASNET_EXTENDED_COLL_DCMF_H_

#include <gasnet_core_internal.h>
#include <gasnet_extended_refcoll.h>
#include <gasnet_coll.h>
#include <gasnet_coll_internal.h>
#include <gasnet_coll_autotune_internal.h>

#include <gasnet_coll_barrier_dcmf.h>

/**
 * data structure for storing dcmf team information  
 */
typedef struct {
  /* struct gasnete_coll_team_t_ baseteam; */
  DCMF_CollectiveRequest_t barrier_req;
  DCMF_CollectiveRequest_t named_barrier_req;
  DCMF_Geometry_t geometry;
  DCMF_CollectiveProtocol_t *bcast_proto;
  DCMF_CollectiveProtocol_t *a2a_proto;
  DCMF_CollectiveProtocol_t *allreduce_proto;
  DCMF_CollectiveProtocol_t *named_barrier_proto;
  volatile int barrier_state; /* enum gasnete_dcmf_barrier_state_t */
} gasnete_coll_team_dcmf_t;  

extern int gasnete_coll_dcmf_inited;

/* global flag to indicate whether to use the DCMF collectives or not */
extern int gasnete_use_dcmf_coll;

/* global flag to indicate if there is a DCMF collective operation executing */
extern volatile int gasnete_dcmf_busy;

/**
 * Initialize the dcmf data structures for gasnet team, used in the
 * DCMF conduit.
 */
void gasnete_dcmf_team_init(gasnet_team_handle_t team,
                            DCMF_CollectiveProtocol_t ** bar_protos,
                            int num_barriers,
                            DCMF_CollectiveProtocol_t ** lbar_protos, 
                            int num_localbarriers);

/**
 * Get the DCMF geometry of the team with team_id
 */
DCMF_Geometry_t * gasnete_dcmf_get_geometry(int team_id);

/* we need these prototypes even when gasnet_coll_internal.h is lacking them: */
extern void gasnete_coll_init_dcmf(void);
extern void gasnete_coll_team_init_dcmf(gasnet_team_handle_t team);

#endif /* GASNET_EXTENDED_COLL_DCMF_H_ */
