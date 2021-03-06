%%%-------------------------------------------------------------------
%%% @copyright (C) 2018, Aeternity Anstalt
%%%-------------------------------------------------------------------
-module(aec_block_key_candidate_tests).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-include("blocks.hrl").

-import(aec_headers, [raw_header/0]).

-import(aec_blocks, [raw_block/0]).

-define(PREV_MINER_PUBKEY, <<85:?MINER_PUB_BYTES/unit:8>>).
-define(MINER_PUBKEY, <<42:?MINER_PUB_BYTES/unit:8>>).
-define(BENEFICIARY_PUBKEY, <<123:?MINER_PUB_BYTES/unit:8>>).

new_key_block_test_() ->
    {"Create new key-block",
     fun() ->
             %% Previous block is a key block, so it
             %% has miner and height.
             RawBlock  = raw_block(),
             PrevBlock1 = aec_blocks:set_height(RawBlock, 11),
             PrevBlock2 = aec_blocks:set_target(PrevBlock1, 17),
             PrevBlock = aec_blocks:set_miner(PrevBlock2, ?MINER_PUBKEY),
             BlockHeader = aec_blocks:to_header(PrevBlock),

             {NewBlock, _} = aec_test_utils:create_keyblock_with_state(
                               [{PrevBlock, aec_trees:new()}], ?MINER_PUBKEY, ?BENEFICIARY_PUBKEY),

             ?assertEqual(12, aec_blocks:height(NewBlock)),
             SerializedBlockHeader = aec_headers:serialize_to_binary(BlockHeader),
             ?assertEqual(aec_hash:hash(header, SerializedBlockHeader),
                          aec_blocks:prev_hash(NewBlock)),
             ?assertEqual([], aec_blocks:txs(NewBlock)),
             ?assertEqual(17, aec_blocks:target(NewBlock)),
             ?assertEqual(?GENESIS_VERSION, aec_blocks:version(NewBlock)),
             ?assertEqual(?MINER_PUBKEY, aec_blocks:miner(NewBlock)),
             ?assertEqual(?BENEFICIARY_PUBKEY, aec_blocks:beneficiary(NewBlock))
     end}.

difficulty_recalculation_test_() ->
      [ {"For good mining speed mine block with almost the same difficulty",
         fun() ->
                 Now            = 1504731164584,
                 GoodDifficulty = 50.0,
                 GoodTarget     = aec_pow:integer_to_scientific(round(?HIGHEST_TARGET_INT / GoodDifficulty)),
                 Height0        = 30,

                 Block0 = aec_blocks:new_key(Height0, <<0:32/unit:8>>, <<0:32/unit:8>>, undefined,
                                             12345, Now, ?PROTOCOL_VERSION, ?MINER_PUBKEY, ?BENEFICIARY_PUBKEY),

                 Chain = compute_chain(Now, Height0, GoodTarget, 0),

                 {ok, Block} = aec_block_key_candidate:adjust_target(Block0, Chain),

                 NewDifficulty = ?HIGHEST_TARGET_INT / aec_pow:scientific_to_integer(aec_blocks:target(Block)),

                 %% The target adjustment algorithm will temper the solvetime slightly, thus the
                 %% new Difficulty should be 0.23% less than the GoodDifficulty
                 ?assert(NewDifficulty * 1.0022 < GoodDifficulty),
                 ?assert(NewDifficulty * 1.0024 > GoodDifficulty)
         end},
        {"Too few blocks mined in time increases new block's target threshold",
         fun() ->
                 Now                      = 1504731164584,
                 Offset                   = round(aec_governance:expected_block_mine_rate() * 0.05),
                 GoodDifficulty           = 50.0,
                 GoodTarget               = aec_pow:integer_to_scientific(round(?HIGHEST_TARGET_INT / GoodDifficulty)),
                 Height0                  = 30,

                 Block0 = aec_blocks:new_key(Height0, <<0:32/unit:8>>, <<0:32/unit:8>>, undefined,
                                             12345, Now, ?PROTOCOL_VERSION, ?MINER_PUBKEY, ?BENEFICIARY_PUBKEY),

                 %% Compute chain with almost perfect timing
                 Chain = compute_chain(Now, Height0, GoodTarget, Offset),

                 {ok, Block} = aec_block_key_candidate:adjust_target(Block0, Chain),

                 NewDifficulty = ?HIGHEST_TARGET_INT / aec_pow:scientific_to_integer(aec_blocks:target(Block)),
                 ?assert(NewDifficulty < GoodDifficulty),
                 ?assert(?HIGHEST_TARGET_SCI > aec_blocks:target(Block))
         end},
        {"Too many blocks mined in time decreases new block's target threshold",
         fun() ->
                 Now                      = 1504731164584,
                 Offset                   = round(aec_governance:expected_block_mine_rate() * 0.05),
                 GoodDifficulty           = 50.0,
                 GoodTarget               = aec_pow:integer_to_scientific(round(?HIGHEST_TARGET_INT / GoodDifficulty)),
                 Height0                  = 30,

                 Block0 = aec_blocks:new_key(Height0, <<0:32/unit:8>>, <<0:32/unit:8>>, undefined,
                                             12345, Now, ?PROTOCOL_VERSION, ?MINER_PUBKEY, ?BENEFICIARY_PUBKEY),

                 %% Compute chain with almost perfect timing
                 Chain = compute_chain(Now, Height0, GoodTarget, -Offset),

                 {ok, Block} = aec_block_key_candidate:adjust_target(Block0, Chain),

                 NewDifficulty = ?HIGHEST_TARGET_INT / aec_pow:scientific_to_integer(aec_blocks:target(Block)),
                 ?assert(NewDifficulty > GoodDifficulty),
                 ?assert(?HIGHEST_TARGET_SCI > aec_blocks:target(Block))
         end}
      ].

compute_chain(Now, Height, Target, MiningOffset) ->
    MineTime = aec_governance:expected_block_mine_rate() + MiningOffset,
    N        = aec_governance:key_blocks_to_check_difficulty_count(),
    RawHeader = raw_header(),
    lists:foldr(fun(H, Bs) ->
                    H1 = aec_headers:set_version_and_height(RawHeader, ?PROTOCOL_VERSION, H),
                    H2 = aec_headers:set_target(H1, Target),
                    [aec_headers:set_time_in_msecs(H2, Now - ((Height - H) * MineTime)) | Bs]
                end, [], lists:seq(Height - (N + 1), Height - 1)).

-endif.
